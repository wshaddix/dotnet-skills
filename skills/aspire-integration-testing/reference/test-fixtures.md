# Test Fixtures

## Pattern 1: Basic Aspire Test Fixture (Modern API)

```csharp
using Aspire.Hosting;
using Aspire.Hosting.Testing;

public sealed class AspireAppFixture : IAsyncLifetime
{
    private DistributedApplication? _app;

    public DistributedApplication App => _app
        ?? throw new InvalidOperationException("App not initialized");

    public async Task InitializeAsync()
    {
        // Pass configuration overrides as command-line args (cleaner than Configuration dictionary)
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.YourApp_AppHost>([
                "YourApp:UseVolumes=false",           // No persistence - clean slate each test
                "YourApp:Environment=IntegrationTest",
                "YourApp:Replicas=1"                  // Single instance for tests
            ]);

        _app = await builder.BuildAsync();

        // Phase 1: Start the application (container startup)
        using var startupCts = new CancellationTokenSource(TimeSpan.FromMinutes(10));
        await _app.StartAsync(startupCts.Token);

        // Phase 2: Wait for services to become healthy (use built-in API)
        using var healthCts = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        await _app.ResourceNotifications.WaitForResourceHealthyAsync("api", healthCts.Token);
    }

    public Uri GetEndpoint(string resourceName, string scheme = "https")
    {
        return _app?.GetEndpoint(resourceName, scheme)
            ?? throw new InvalidOperationException($"Endpoint for '{resourceName}' not found");
    }

    public async Task DisposeAsync()
    {
        if (_app is not null)
        {
            await _app.DisposeAsync();
        }
    }
}
```

## Pattern 2: Using the Fixture in Tests

```csharp
// Define a collection to share the fixture across multiple test classes
[CollectionDefinition("Aspire collection")]
public class AspireCollection : ICollectionFixture<AspireAppFixture> { }

// Use the fixture in your test class
[Collection("Aspire collection")]
public class IntegrationTests
{
    private readonly AspireAppFixture _fixture;

    public IntegrationTests(AspireAppFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task Application_ShouldStart()
    {
        // Get the web application resource
        var webApp = _fixture.App.GetResource("yourapp");

        // Get the HTTP endpoint
        var httpClient = _fixture.App.CreateHttpClient("yourapp");

        // Make a request
        var response = await httpClient.GetAsync("/");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
```

## Pattern 3: Database Reset with Respawn

For tests that modify data, use [Respawn](https://github.com/jbogard/Respawn) to reset between tests:

```csharp
using Respawn;

public class AspireFixtureWithReset : IAsyncLifetime
{
    private DistributedApplication? _app;
    private Respawner? _respawner;
    private string? _connectionString;

    public async Task InitializeAsync()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.YourApp_AppHost>([
                "YourApp:UseVolumes=false"
            ]);

        _app = await builder.BuildAsync();
        await _app.StartAsync();

        // Wait for database and migrations
        await _app.ResourceNotifications.WaitForResourceHealthyAsync("api");

        // Get connection string and create respawner
        var dbResource = _app.GetResource("appdb");
        _connectionString = await dbResource.GetConnectionStringAsync();

        _respawner = await Respawner.CreateAsync(_connectionString, new RespawnerOptions
        {
            TablesToIgnore = new[]
            {
                "__EFMigrationsHistory",
                "schema_version",        // DbUp
                "AspNetRoles"            // Seeded reference data
            },
            DbAdapter = DbAdapter.Postgres
        });
    }

    /// <summary>
    /// Reset database to clean state between tests.
    /// </summary>
    public async Task ResetDatabaseAsync()
    {
        if (_respawner is not null && _connectionString is not null)
        {
            await _respawner.ResetAsync(_connectionString);
        }
    }

    public async Task DisposeAsync()
    {
        if (_app is not null)
            await _app.DisposeAsync();
    }
}
```

## Fixture Lifecycle with Health Checks

```csharp
public static class ResourceExtensions
{
    public static async Task WaitForHealthyAsync(
        this DistributedApplication app,
        string resourceName,
        TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(30);
        var cts = new CancellationTokenSource(timeout.Value);

        var resource = app.GetResource(resourceName);

        while (!cts.Token.IsCancellationRequested)
        {
            try
            {
                var httpClient = app.CreateHttpClient(resourceName);
                var response = await httpClient.GetAsync(
                    "/health",
                    cts.Token);

                if (response.IsSuccessStatusCode)
                    return;
            }
            catch
            {
                // Resource not ready yet
            }

            await Task.Delay(500, cts.Token);
        }

        throw new TimeoutException(
            $"Resource '{resourceName}' did not become healthy within {timeout}");
    }
}

// Usage
[Fact]
public async Task ServicesShouldBeHealthy()
{
    await _fixture.App.WaitForHealthyAsync("yourapp");
    await _fixture.App.WaitForHealthyAsync("youra pi");

    // Now proceed with tests
}
```

## Test Class Organization with Collections

Use xUnit collections to control test parallelization and share fixtures:

```csharp
// Define a collection to share the fixture across multiple test classes
[CollectionDefinition("Aspire collection")]
public class AspireCollection : ICollectionFixture<AspireAppFixture> { }

// Multiple test classes can share the same fixture
[Collection("Aspire collection")]
public class UserApiTests { /* ... */ }

[Collection("Aspire collection")]
public class OrderApiTests { /* ... */ }
```

Collections ensure that tests within the same collection run sequentially, avoiding conflicts when sharing the same application instance.

## Advanced: Custom Resource Waiters

```csharp
public static class ResourceWaiters
{
    public static async Task WaitForSqlServerAsync(
        this DistributedApplication app,
        string resourceName,
        CancellationToken ct = default)
    {
        var resource = app.GetResource(resourceName);
        var connectionString = await resource.GetConnectionStringAsync(ct);

        var retryCount = 0;
        const int maxRetries = 30;

        while (retryCount < maxRetries)
        {
            try
            {
                await using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync(ct);
                return; // Success!
            }
            catch (SqlException)
            {
                retryCount++;
                await Task.Delay(1000, ct);
            }
        }

        throw new TimeoutException(
            $"SQL Server resource '{resourceName}' did not become ready");
    }

    public static async Task WaitForRedisAsync(
        this DistributedApplication app,
        string resourceName,
        CancellationToken ct = default)
    {
        var resource = app.GetResource(resourceName);
        var connectionString = await resource.GetConnectionStringAsync(ct);

        var retryCount = 0;
        const int maxRetries = 30;

        while (retryCount < maxRetries)
        {
            try
            {
                var redis = await ConnectionMultiplexer.ConnectAsync(
                    connectionString);
                await redis.GetDatabase().PingAsync();
                return; // Success!
            }
            catch
            {
                retryCount++;
                await Task.Delay(1000, ct);
            }
        }

        throw new TimeoutException(
            $"Redis resource '{resourceName}' did not become ready");
    }
}

// Usage
public async Task InitializeAsync()
{
    _app = await appHost.BuildAsync();
    await _app.StartAsync();

    // Wait for dependencies to be ready
    await _app.WaitForSqlServerAsync("yourdb");
    await _app.WaitForRedisAsync("cache");
}
```
