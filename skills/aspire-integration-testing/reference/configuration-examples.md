# Configuration Examples

## Resource Configuration

### Configuration Class in AppHost

```csharp
// In your AppHost project
public class AppHostConfiguration
{
    // Infrastructure settings
    public bool UseVolumes { get; set; } = true;  // Persist data in dev, clean slate in tests

    // Execution mode settings (for Akka.NET or similar)
    public string ExecutionMode { get; set; } = "Clustered";  // Full cluster in dev, LocalTest optional

    // Feature toggles
    public bool EnableTestAuth { get; set; } = false;  // /dev-login endpoint for tests
    public bool UseFakeExternalServices { get; set; } = false;  // Fake Gmail, Stripe, etc.

    // Scale settings
    public int Replicas { get; set; } = 1;
}
```

### AppHost Conditional Logic

```csharp
var builder = DistributedApplication.CreateBuilder(args);

// Bind configuration from command-line args or appsettings
var config = builder.Configuration.GetSection("App")
    .Get<AppHostConfiguration>() ?? new AppHostConfiguration();

// Database with conditional volume
var postgres = builder.AddPostgres("postgres").WithPgAdmin();
if (config.UseVolumes)
{
    postgres.WithDataVolume();
}
var db = postgres.AddDatabase("appdb");

// Migrations
var migrations = builder.AddProject<Projects.YourApp_Migrations>("migrations")
    .WaitFor(db)
    .WithReference(db);

// API with environment-based configuration
var api = builder.AddProject<Projects.YourApp_Api>("api")
    .WaitForCompletion(migrations)
    .WithReference(db)
    .WithEnvironment("AkkaSettings__ExecutionMode", config.ExecutionMode)
    .WithEnvironment("Testing__EnableTestAuth", config.EnableTestAuth.ToString())
    .WithEnvironment("ExternalServices__UseFakes", config.UseFakeExternalServices.ToString());

// Conditional replicas
if (config.Replicas > 1)
{
    api.WithReplicas(config.Replicas);
}

builder.Build().Run();
```

## Environment Variable Configuration

### Test Fixture Overrides

```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.YourApp_AppHost>([
        "App:UseVolumes=false",           // Clean database each test
        "App:ExecutionMode=LocalTest",    // Faster, no cluster overhead (optional)
        "App:EnableTestAuth=true",        // Enable /dev-login endpoint
        "App:UseFakeExternalServices=true" // No real OAuth, email, payments
    ]);
```

### Common Conditional Settings

| Setting | F5/Development | Test Fixture | Purpose |
|---------|----------------|--------------|---------|
| `UseVolumes` | `true` (persist data) | `false` (clean slate) | Database isolation |
| `ExecutionMode` | `Clustered` (realistic) | `LocalTest` or `Clustered` | Actor system mode |
| `EnableTestAuth` | `false` (use real OAuth) | `true` (/dev-login) | Bypass OAuth in tests |
| `UseFakeServices` | `false` (real integrations) | `true` (no external calls) | External API isolation |
| `Replicas` | `1` or more | `1` (simplicity) | Scale configuration |
| `SeedData` | `false` | `true` | Pre-populate test data |

### Test Authentication Pattern

When `EnableTestAuth=true`, your API can expose a test-only authentication endpoint:

```csharp
// In API startup, conditionally add test auth
if (builder.Configuration.GetValue<bool>("Testing:EnableTestAuth"))
{
    app.MapPost("/dev-login", async (DevLoginRequest request, IAuthService auth) =>
    {
        // Generate a real auth token for the specified user
        var token = await auth.GenerateTokenAsync(request.UserId, request.Roles);
        return Results.Ok(new { token });
    });
}

// In tests
public async Task<string> LoginAsTestUser(string userId, string[] roles)
{
    var response = await _httpClient.PostAsJsonAsync("/dev-login",
        new { UserId = userId, Roles = roles });
    var result = await response.Content.ReadFromJsonAsync<DevLoginResponse>();
    return result!.Token;
}
```

### Fake External Services Pattern

```csharp
// In your service registration
public static IServiceCollection AddExternalServices(
    this IServiceCollection services,
    IConfiguration config)
{
    if (config.GetValue<bool>("ExternalServices:UseFakes"))
    {
        // Test fakes - no external calls
        services.AddSingleton<IEmailSender, FakeEmailSender>();
        services.AddSingleton<IPaymentProcessor, FakePaymentProcessor>();
        services.AddSingleton<IOAuthProvider, FakeOAuthProvider>();
    }
    else
    {
        // Real implementations
        services.AddSingleton<IEmailSender, SendGridEmailSender>();
        services.AddSingleton<IPaymentProcessor, StripePaymentProcessor>();
        services.AddSingleton<IOAuthProvider, Auth0Provider>();
    }

    return services;
}
```

## Wait Strategies

### Basic Health Check Wait

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

### Built-in Resource Health Wait

```csharp
public async Task InitializeAsync()
{
    var builder = await DistributedApplicationTestingBuilder
        .CreateAsync<Projects.YourApp_AppHost>([
            "YourApp:UseVolumes=false",
            "YourApp:Environment=IntegrationTest",
            "YourApp:Replicas=1"
        ]);

    _app = await builder.BuildAsync();

    // Phase 1: Start the application (container startup)
    using var startupCts = new CancellationTokenSource(TimeSpan.FromMinutes(10));
    await _app.StartAsync(startupCts.Token);

    // Phase 2: Wait for services to become healthy (use built-in API)
    using var healthCts = new CancellationTokenSource(TimeSpan.FromMinutes(5));
    await _app.ResourceNotifications.WaitForResourceHealthyAsync("api", healthCts.Token);
}
```

### Custom Resource Waiters

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
