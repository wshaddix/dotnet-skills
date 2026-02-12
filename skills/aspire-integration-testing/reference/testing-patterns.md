# Testing Patterns

## Pattern 1: Testing Individual Services

```csharp
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

## Pattern 2: Testing Service-to-Service Communication

```csharp
[Fact]
public async Task WebApp_ShouldCallApi()
{
    var webClient = _fixture.App.CreateHttpClient("webapp");
    var apiClient = _fixture.App.CreateHttpClient("api");

    // Verify API is accessible
    var apiResponse = await apiClient.GetAsync("/api/data");
    Assert.True(apiResponse.IsSuccessStatusCode);

    // Verify WebApp calls API correctly
    var webResponse = await webClient.GetAsync("/fetch-data");
    Assert.True(webResponse.IsSuccessStatusCode);

    var content = await webResponse.Content.ReadAsStringAsync();
    Assert.NotEmpty(content);
}
```

## Pattern 3: Testing with Real Databases

```csharp
public class DatabaseIntegrationTests
{
    private readonly AspireAppFixture _fixture;

    public DatabaseIntegrationTests(AspireAppFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task Database_ShouldBeInitialized()
    {
        // Get connection string from Aspire
        var dbResource = _fixture.App.GetResource("yourdb");
        var connectionString = await dbResource
            .GetConnectionStringAsync();

        // Test database access
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();

        var result = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES");

        Assert.True(result > 0, "Database should have tables");
    }
}
```

## Pattern 4: Testing with Message Brokers

```csharp
[Fact]
public async Task MessageQueue_ShouldProcessMessages()
{
    // Get RabbitMQ connection from Aspire
    var rabbitMqResource = _fixture.App.GetResource("messaging");
    var connectionString = await rabbitMqResource
        .GetConnectionStringAsync();

    var factory = new ConnectionFactory
    {
        Uri = new Uri(connectionString)
    };

    using var connection = await factory.CreateConnectionAsync();
    using var channel = await connection.CreateChannelAsync();

    // Publish a test message
    await channel.QueueDeclareAsync("test-queue", durable: false);
    await channel.BasicPublishAsync(
        exchange: "",
        routingKey: "test-queue",
        body: Encoding.UTF8.GetBytes("test message"));

    // Wait for processing
    await Task.Delay(1000);

    // Verify message was processed
    // (check database, file system, or other side effects)
}
```

## Pattern 5: Combining with Playwright for UI Tests

```csharp
using Microsoft.Playwright;

public sealed class AspirePlaywrightFixture : IAsyncLifetime
{
    private DistributedApplication? _app;
    private IPlaywright? _playwright;
    private IBrowser? _browser;

    public DistributedApplication App => _app!;
    public IBrowser Browser => _browser!;

    public async Task InitializeAsync()
    {
        // Start Aspire application
        var appHost = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.YourApp_AppHost>();

        _app = await appHost.BuildAsync();
        await _app.StartAsync();

        // Wait for app to be fully ready
        await Task.Delay(2000); // Or use proper health check polling

        // Start Playwright
        _playwright = await Playwright.CreateAsync();
        _browser = await _playwright.Chromium.LaunchAsync(new()
        {
            Headless = true
        });
    }

    public async Task DisposeAsync()
    {
        if (_browser is not null)
            await _browser.DisposeAsync();

        _playwright?.Dispose();

        if (_app is not null)
            await _app.DisposeAsync();
    }
}

[Collection("Aspire Playwright collection")]
public class UIIntegrationTests
{
    private readonly AspirePlaywrightFixture _fixture;

    public UIIntegrationTests(AspirePlaywrightFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task HomePage_ShouldLoad()
    {
        var url = _fixture.App.GetEndpointUrl("yourapp");
        var page = await _fixture.Browser.NewPageAsync();

        await page.GotoAsync(url);

        var title = await page.TitleAsync();
        Assert.NotEmpty(title);
    }
}
```

## Endpoint Discovery Pattern

```csharp
public static class DistributedApplicationExtensions
{
    public static ResourceEndpoint GetEndpoint(
        this DistributedApplication app,
        string resourceName,
        string? endpointName = null)
    {
        var resource = app.GetResource(resourceName);

        if (resource is null)
            throw new InvalidOperationException(
                $"Resource '{resourceName}' not found");

        var endpoint = endpointName is null
            ? resource.GetEndpoints().FirstOrDefault()
            : resource.GetEndpoint(endpointName);

        if (endpoint is null)
            throw new InvalidOperationException(
                $"Endpoint '{endpointName}' not found on resource '{resourceName}'");

        return endpoint;
    }

    public static string GetEndpointUrl(
        this DistributedApplication app,
        string resourceName,
        string? endpointName = null)
    {
        var endpoint = app.GetEndpoint(resourceName, endpointName);
        return endpoint.Url;
    }
}

// Usage in tests
[Fact]
public async Task CanAccessWebApplication()
{
    var url = _fixture.App.GetEndpointUrl("yourapp");
    var client = new HttpClient { BaseAddress = new Uri(url) };

    var response = await client.GetAsync("/health");

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
}
```
