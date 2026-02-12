---
name: http-client-resilience
description: IHttpClientFactory patterns with Polly for retries, circuit breakers, timeouts, and resilient HTTP communication. Includes best practices for HTTP client configuration and error handling. Use when configuring resilient HTTP clients in ASP.NET Core, implementing retry policies with Polly, or setting up circuit breakers for external service calls.
---

## Rationale

HTTP calls to external services are inherently unreliable. Network issues, service outages, and transient failures are common in distributed systems. Without proper resilience patterns, your application will experience cascading failures. These patterns using `IHttpClientFactory` and Polly provide production-grade reliability for HTTP communication.

## Patterns

### Pattern 1: Named HttpClient with Resilience

Configure named clients with comprehensive resilience policies including retry, circuit breaker, and timeout.

```csharp
// Program.cs - Configuration
builder.Services.AddHttpClient("PaymentApi", client =>
{
    client.BaseAddress = new Uri("https://api.payment-provider.com/v1/");
    client.Timeout = TimeSpan.FromSeconds(30);
    client.DefaultRequestHeaders.Add("Accept", "application/json");
    client.DefaultRequestHeaders.Add("X-API-Key", builder.Configuration["PaymentApi:Key"]!);
})
.AddStandardResilienceHandler(options =>
{
    // Retry configuration
    options.Retry.MaxRetryAttempts = 3;
    options.Retry.Delay = TimeSpan.FromSeconds(1);
    options.Retry.BackoffType = DelayBackoffType.Exponential;
    
    // Circuit breaker configuration
    options.CircuitBreaker.SamplingDuration = TimeSpan.FromMinutes(1);
    options.CircuitBreaker.FailureRatio = 0.5;
    options.CircuitBreaker.MinimumThroughput = 10;
    options.CircuitBreaker.BreakDuration = TimeSpan.FromSeconds(30);
    
    // Timeout configuration
    options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(10);
    options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(30);
});

// Typed client for type-safe usage
public interface IPaymentClient
{
    Task<PaymentResult> ProcessPaymentAsync(PaymentRequest request, CancellationToken ct = default);
    Task<RefundResult> ProcessRefundAsync(string transactionId, CancellationToken ct = default);
}

public class PaymentClient : IPaymentClient
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<PaymentClient> _logger;

    public PaymentClient(IHttpClientFactory httpClientFactory, ILogger<PaymentClient> logger)
    {
        _httpClient = httpClientFactory.CreateClient("PaymentApi");
        _logger = logger;
    }

    public async Task<PaymentResult> ProcessPaymentAsync(PaymentRequest request, CancellationToken ct = default)
    {
        var response = await _httpClient.PostAsJsonAsync("payments", request, ct);
        
        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            _logger.LogWarning("Payment API rate limit hit");
            throw new PaymentRateLimitException("Payment provider is experiencing high load");
        }

        response.EnsureSuccessStatusCode();
        
        return await response.Content.ReadFromJsonAsync<PaymentResult>(ct)
            ?? throw new PaymentException("Invalid response from payment provider");
    }

    public async Task<RefundResult> ProcessRefundAsync(string transactionId, CancellationToken ct = default)
    {
        var response = await _httpClient.PostAsync($"payments/{transactionId}/refund", null, ct);
        response.EnsureSuccessStatusCode();
        
        return await response.Content.ReadFromJsonAsync<RefundResult>(ct)
            ?? throw new PaymentException("Invalid response");
    }
}
```

### Pattern 2: Custom Resilience Pipeline with Polly

For advanced scenarios, build custom Polly pipelines with specific handling for different failure types.

```csharp
// Custom resilience pipeline configuration
builder.Services.AddResiliencePipeline("critical-api", builder =>
{
    // Add retry with specific handling
    builder.AddRetry(new RetryStrategyOptions<HttpResponseMessage>
    {
        MaxRetryAttempts = 5,
        Delay = TimeSpan.FromSeconds(2),
        BackoffType = DelayBackoffType.Exponential,
        ShouldHandle = args => args.Outcome switch
        {
            { Result: { StatusCode: HttpStatusCode.TooManyRequests } } => PredicateResult.True(),
            { Result: { StatusCode: HttpStatusCode.ServiceUnavailable } } => PredicateResult.True(),
            { Result: { StatusCode: HttpStatusCode.GatewayTimeout } } => PredicateResult.True(),
            { Exception: HttpRequestException } => PredicateResult.True(),
            { Exception: TimeoutRejectedException } => PredicateResult.True(),
            _ => PredicateResult.False()
        },
        OnRetry = args =>
        {
            Console.WriteLine($"Retry {args.AttemptNumber} for {args.Outcome.Result?.RequestMessage?.RequestUri}");
            return ValueTask.CompletedTask;
        }
    });

    // Add circuit breaker
    builder.AddCircuitBreaker(new CircuitBreakerStrategyOptions<HttpResponseMessage>
    {
        SamplingDuration = TimeSpan.FromMinutes(2),
        FailureRatio = 0.6,
        MinimumThroughput = 20,
        BreakDuration = TimeSpan.FromMinutes(2),
        ShouldHandle = args => args.Outcome.Result?.IsSuccessStatusCode is false 
            ? PredicateResult.True() 
            : PredicateResult.False(),
        OnOpened = args =>
        {
            Console.WriteLine($"Circuit opened! {args.FailureRatio * 100}% failure rate");
            return ValueTask.CompletedTask;
        },
        OnClosed = args =>
        {
            Console.WriteLine("Circuit closed - service recovered");
            return ValueTask.CompletedTask;
        }
    });

    // Add timeout per attempt
    builder.AddTimeout(TimeSpan.FromSeconds(15));
});

// Usage with typed client
public class InventoryClient
{
    private readonly HttpClient _httpClient;
    private readonly ResiliencePipeline<HttpResponseMessage> _pipeline;

    public InventoryClient(
        IHttpClientFactory factory,
        ResiliencePipelineProvider<HttpResponseMessage> pipelineProvider)
    {
        _httpClient = factory.CreateClient("InventoryApi");
        _pipeline = pipelineProvider.GetPipeline("critical-api");
    }

    public async Task<StockLevel> GetStockAsync(string sku, CancellationToken ct = default)
    {
        var response = await _pipeline.ExecuteAsync(
            async token => await _httpClient.GetAsync($"stock/{sku}", token),
            ct);

        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<StockLevel>(ct)
            ?? throw new InvalidOperationException("Invalid response");
    }
}
```

### Pattern 3: Razor Pages Integration

Properly integrate HTTP clients in Razor Pages with proper disposal and error handling.

```csharp
// Typed client registration
builder.Services.AddHttpClient<IGeoLocationService, GeoLocationService>(client =>
{
    client.BaseAddress = new Uri("https://api.geolocation.com/");
    client.Timeout = TimeSpan.FromSeconds(10);
})
.AddStandardResilienceHandler(options =>
{
    options.Retry.MaxRetryAttempts = 3;
    options.CircuitBreaker.BreakDuration = TimeSpan.FromSeconds(60);
});

// Service implementation
public interface IGeoLocationService
{
    Task<LocationInfo?> GetLocationAsync(string ipAddress, CancellationToken ct = default);
}

public class GeoLocationService : IGeoLocationService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<GeoLocationService> _logger;

    public GeoLocationService(HttpClient httpClient, ILogger<GeoLocationService> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<LocationInfo?> GetLocationAsync(string ipAddress, CancellationToken ct = default)
    {
        try
        {
            var response = await _httpClient.GetAsync($"json/{ipAddress}", ct);
            
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return null;
            }

            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<LocationInfo>(ct);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Failed to get location for IP {Ip}", ipAddress);
            return null; // Graceful degradation
        }
    }
}

// PageModel usage
public class AnalyticsModel : PageModel
{
    private readonly IGeoLocationService _geoService;
    private readonly ILogger<AnalyticsModel> _logger;

    [BindProperty]
    public LocationInfo? Location { get; set; }

    public string? ErrorMessage { get; set; }

    public async Task OnGetAsync()
    {
        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "8.8.8.8";
        
        try
        {
            Location = await _geoService.GetLocationAsync(ipAddress);
            
            if (Location is null)
            {
                ErrorMessage = "Unable to determine location";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in analytics page");
            ErrorMessage = "Service temporarily unavailable";
        }
    }
}
```

### Pattern 4: Request/Response Logging and Headers

Implement proper logging and custom headers for observability and authentication.

```csharp
// Delegating handler for request/response logging
public class LoggingHandler : DelegatingHandler
{
    private readonly ILogger<LoggingHandler> _logger;

    public LoggingHandler(ILogger<LoggingHandler> logger)
    {
        _logger = logger;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var requestId = Guid.NewGuid().ToString("N")[..8];
        request.Headers.Add("X-Request-ID", requestId);

        _logger.LogInformation(
            "[{RequestId}] HTTP {Method} {Uri}",
            requestId,
            request.Method,
            request.RequestUri);

        var stopwatch = Stopwatch.StartNew();
        
        try
        {
            var response = await base.SendAsync(request, cancellationToken);
            stopwatch.Stop();

            _logger.LogInformation(
                "[{RequestId}] HTTP {StatusCode} in {ElapsedMs}ms",
                requestId,
                (int)response.StatusCode,
                stopwatch.ElapsedMilliseconds);

            return response;
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(
                ex,
                "[{RequestId}] HTTP request failed after {ElapsedMs}ms",
                requestId,
                stopwatch.ElapsedMilliseconds);
            throw;
        }
    }
}

// Authentication handler
public class ApiKeyHandler : DelegatingHandler
{
    private readonly string _apiKey;

    public ApiKeyHandler(string apiKey)
    {
        _apiKey = apiKey;
    }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
        return base.SendAsync(request, cancellationToken);
    }
}

// Registration with handlers
builder.Services.AddTransient<LoggingHandler>();

builder.Services.AddHttpClient("SecureApi", (sp, client) =>
{
    client.BaseAddress = new Uri("https://api.secure-service.com/");
})
.AddHttpMessageHandler<LoggingHandler>()
.AddHttpMessageHandler(sp => new ApiKeyHandler(
    sp.GetRequiredService<IConfiguration>()["ApiKeys:SecureService"]!));
```

### Pattern 5: Health Check Integration

Integrate HTTP client health checks for service monitoring.

```csharp
// Custom health check for external services
public class ExternalApiHealthCheck : IHealthCheck
{
    private readonly IHttpClientFactory _httpClientFactory;

    public ExternalApiHealthCheck(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("PaymentApi");
            var response = await client.GetAsync("health", cancellationToken);

            if (response.IsSuccessStatusCode)
            {
                return HealthCheckResult.Healthy("Payment API is accessible");
            }

            return HealthCheckResult.Degraded(
                $"Payment API returned {response.StatusCode}");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy(
                "Payment API is unreachable", ex);
        }
    }
}

// Registration in Program.cs
builder.Services.AddHealthChecks()
    .AddCheck<ExternalApiHealthCheck>("payment-api");

// Or use built-in URI health check
builder.Services.AddHealthChecks()
    .AddUrlGroup(
        new Uri("https://api.service.com/health"),
        name: "external-service",
        failureStatus: HealthStatus.Degraded,
        tags: new[] { "external" });
```

## Anti-Patterns

```csharp
// ❌ BAD: Using HttpClient directly with 'new'
var client = new HttpClient(); // Socket exhaustion!
var response = await client.GetAsync("https://api.example.com/data");

// ✅ GOOD: Use IHttpClientFactory
public class GoodService
{
    private readonly IHttpClientFactory _factory;
    
    public GoodService(IHttpClientFactory factory) => _factory = factory;
    
    public async Task GetDataAsync()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("https://api.example.com/data");
    }
}

// ❌ BAD: Static/shared HttpClient instance
public class BadService
{
    private static readonly HttpClient _client = new(); // DNS changes not respected!
    
    public async Task GetDataAsync()
    {
        var response = await _client.GetAsync("...");
    }
}

// ❌ BAD: No timeout handling
public async Task<string> FetchDataAsync()
{
    var client = _factory.CreateClient();
    var response = await client.GetAsync("https://slow-api.com/data"); // Hangs forever!
    return await response.Content.ReadAsStringAsync();
}

// ✅ GOOD: Set timeout and handle cancellation
public async Task<string?> FetchDataAsync(CancellationToken ct)
{
    var client = _factory.CreateClient();
    client.Timeout = TimeSpan.FromSeconds(10);
    
    try
    {
        var response = await client.GetAsync("https://slow-api.com/data", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync(ct);
    }
    catch (TaskCanceledException ex) when (ex.InnerException is TimeoutException)
    {
        _logger.LogError("Request timed out");
        return null;
    }
}

// ❌ BAD: Swallowing HTTP errors without context
try
{
    var response = await client.GetAsync("/api/data");
    return await response.Content.ReadFromJsonAsync<Data>();
}
catch (Exception ex)
{
    _logger.LogError(ex, "Request failed"); // No context about the failure
    return null;
}

// ✅ GOOD: Specific error handling with context
try
{
    var response = await client.GetAsync("/api/data", ct);
    
    if (response.StatusCode == HttpStatusCode.NotFound)
    {
        _logger.LogWarning("Data not found for ID {Id}", id);
        return null;
    }
    
    if (response.StatusCode == HttpStatusCode.TooManyRequests)
    {
        _logger.LogWarning("Rate limited by external API");
        throw new RateLimitException("Please try again later");
    }
    
    response.EnsureSuccessStatusCode();
    return await response.Content.ReadFromJsonAsync<Data>(ct);
}
catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.ServiceUnavailable)
{
    _logger.LogError(ex, "External service unavailable");
    throw new ServiceUnavailableException("Service temporarily unavailable");
}

// ❌ BAD: Not disposing HttpResponseMessage
var response = await client.GetAsync("/api/data");
return await response.Content.ReadAsStringAsync();

// ✅ GOOD: Proper disposal
using var response = await client.GetAsync("/api/data");
response.EnsureSuccessStatusCode();
return await response.Content.ReadAsStringAsync();

// ❌ BAD: Blocking in async context
public string GetData()
{
    var client = _factory.CreateClient();
    var response = client.GetAsync("/api/data").Result; // Deadlock risk!
    return response.Content.ReadAsStringAsync().Result;
}

// ✅ GOOD: Async all the way
public async Task<string> GetDataAsync(CancellationToken ct)
{
    var client = _factory.CreateClient();
    using var response = await client.GetAsync("/api/data", ct);
    return await response.Content.ReadAsStringAsync(ct);
}
```

## References

- [IHttpClientFactory in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-requests)
- [Polly Documentation](https://www.pollydocs.org/)
- [Resilience Patterns](https://learn.microsoft.com/en-us/dotnet/core/resilience/)
- [HTTP Client Guidelines](https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines)
