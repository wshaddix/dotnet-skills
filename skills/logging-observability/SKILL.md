---
name: logging-observability
description: Production-grade logging and observability patterns for ASP.NET Core Razor Pages. Covers structured logging with Serilog, correlation IDs, health checks, request logging, OpenTelemetry integration, and diagnostic best practices.
version: 1.0
last-updated: 2026-02-11
tags: [aspnetcore, logging, observability, serilog, monitoring, razor-pages]
---

You are a senior .NET architect specializing in observability. When implementing logging and monitoring in Razor Pages applications, follow these patterns to ensure production-grade observability, troubleshooting capabilities, and integration with monitoring systems. Target .NET 8+ with nullable reference types enabled.

## Rationale

Effective observability is critical for production applications. Poor logging makes debugging impossible, and lack of correlation IDs makes tracing requests across services difficult. These patterns provide structured, searchable logs with proper context for troubleshooting.

## Core Principles

1. **Structured Logging**: Use structured formats (JSON) for machine parsing
2. **Correlation IDs**: Every request gets a unique ID for end-to-end tracing
3. **Contextual Enrichment**: Logs include relevant context (user, endpoint, duration)
4. **Log Levels**: Use appropriate levels (Debug, Info, Warning, Error, Fatal)
5. **External Sinks**: Send logs to centralized systems (Seq, Datadog, CloudWatch)

## Pattern 1: Serilog Configuration

### NuGet Packages

```xml
<PackageReference Include="Serilog.AspNetCore" Version="8.0.*" />
<PackageReference Include="Serilog.Expressions" Version="4.0.*" />
<PackageReference Include="Serilog.Sinks.Seq" Version="7.0.*" /> <!-- Optional -->
```

### Bootstrap Logger (Program.cs Start)

```csharp
using Serilog;
using Serilog.Debugging;

// Enable Serilog self-logging for diagnostics
SelfLog.Enable(msg => Console.Error.WriteLine($"[SERILOG] {msg}"));

// Create bootstrap logger for startup errors
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Information)
    .Enrich.FromLogContext()
    .WriteTo.Console(formatProvider: CultureInfo.CurrentCulture)
    .CreateBootstrapLogger();

try
{
    Log.Information("Starting web application...");
    var builder = WebApplication.CreateBuilder(args);
    
    // ... configure services ...
    
    var app = builder.Build();
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    await Log.CloseAndFlushAsync();
}
```

### Service Registration

```csharp
public static class LoggingServiceRegistration
{
    public static IServiceCollection ConfigureSerilog(
        this IServiceCollection services, 
        IConfiguration configuration)
    {
        services.AddSerilog((services, lc) => lc
            .ReadFrom.Configuration(configuration)
            .Enrich.FromLogContext()
            .Enrich.WithMachineName()
            .Enrich.WithEnvironmentName()
            .WriteTo.Console(formatter: new ExpressionTemplate(
                "[{@t:hh:mm:ss.fff tt} {@l:u3}] {SourceContext} - {CorrelationId} - {@m}\n{@x}",
                theme: TemplateTheme.Code))
            .WriteTo.Seq(
                configuration["Seq:ServerUrl"] ?? "http://localhost:5341",
                apiKey: configuration["Seq:ApiKey"],
                formatProvider: CultureInfo.CurrentCulture)
        );

        return services;
    }
}
```

### appsettings.json Configuration

```json
{
  "Serilog": {
    "Using": ["Serilog.Sinks.Console", "Serilog.Sinks.Seq"],
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.AspNetCore": "Warning",
        "System": "Warning"
      }
    },
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "outputTemplate": "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}"
        }
      }
    ],
    "Enrich": ["FromLogContext", "WithMachineName", "WithThreadId"],
    "Properties": {
      "Application": "MyApp"
    }
  }
}
```

## Pattern 2: Correlation ID Middleware

```csharp
public class RequestContextLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private const string CorrelationHeaderName = "X-Correlation-Id";

    public RequestContextLoggingMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task Invoke(HttpContext httpContext)
    {
        var correlationId = GetCorrelationId(httpContext);
        
        // Add to response headers
        httpContext.Response.OnStarting(() =>
        {
            httpContext.Response.Headers[CorrelationHeaderName] = correlationId;
            return Task.CompletedTask;
        });

        using (LogContext.PushProperty("CorrelationId", correlationId))
        using (LogContext.PushProperty("RequestPath", httpContext.Request.Path))
        using (LogContext.PushProperty("RequestMethod", httpContext.Request.Method))
        {
            await _next.Invoke(httpContext);
        }
    }

    private static string GetCorrelationId(HttpContext httpContext)
    {
        httpContext.Request.Headers.TryGetValue(
            CorrelationHeaderName, out var correlationId);

        return correlationId.FirstOrDefault() ?? httpContext.TraceIdentifier;
    }
}

// Extension method for easy registration
public static class RequestContextLoggingExtensions
{
    public static IApplicationBuilder UseRequestContextLogging(
        this IApplicationBuilder app)
    {
        return app.UseMiddleware<RequestContextLoggingMiddleware>();
    }
}
```

### Registration

```csharp
// Program.cs
var app = builder.Build();

// Place early in pipeline
app.UseRequestContextLogging();
app.UseSerilogRequestLogging(); // Logs each request
```

## Pattern 3: Request Logging with Serilog

```csharp
// Program.cs
app.UseSerilogRequestLogging(options =>
{
    options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
    {
        diagnosticContext.Set("UserId", httpContext.User.Identity?.Name ?? "anonymous");
        diagnosticContext.Set("ClientIp", httpContext.Connection.RemoteIpAddress?.ToString());
        diagnosticContext.Set("UserAgent", httpContext.Request.Headers["User-Agent"].ToString());
    };
    
    options.GetLevel = (httpContext, elapsed, ex) =>
    {
        // Log 5xx as Error, slow requests as Warning
        if (ex != null || httpContext.Response.StatusCode > 499)
            return LogEventLevel.Error;
        
        if (elapsed > 1000)
            return LogEventLevel.Warning;
        
        return LogEventLevel.Information;
    };
});
```

### Custom Request Logging (PageModel)

```csharp
public class OrderDetailsModel(ILogger<OrderDetailsModel> logger) : PageModel
{
    public async Task OnGetAsync(Guid orderId)
    {
        // Push contextual properties
        using (logger.BeginScope(new Dictionary<string, object>
        {
            ["OrderId"] = orderId,
            ["UserId"] = User.Identity?.Name ?? "anonymous"
        }))
        {
            logger.LogInformation("Loading order details");
            
            try
            {
                var order = await _orderService.GetAsync(orderId);
                
                if (order == null)
                {
                    logger.LogWarning("Order not found");
                    return NotFound();
                }
                
                logger.LogInformation("Order loaded successfully");
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to load order");
                throw;
            }
        }
    }
}
```

## Pattern 4: MediatR Pipeline Logging

```csharp
public class RequestLoggingBehavior<TRequest, TResponse>(ILogger<RequestLoggingBehavior<TRequest, TResponse>> logger)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    private static readonly string RequestName = typeof(TRequest).Name;
    private static readonly TimeSpan SlowRequestThreshold = TimeSpan.FromMilliseconds(500);

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Handling {RequestName}", RequestName);

        var stopwatch = Stopwatch.StartNew();

        try
        {
            var response = await next(cancellationToken);

            stopwatch.Stop();
            var elapsed = stopwatch.Elapsed;

            if (elapsed > SlowRequestThreshold)
            {
                logger.LogWarning(
                    "Handled {RequestName} successfully in {ElapsedMs}ms (exceeds {ThresholdMs}ms threshold)",
                    RequestName,
                    elapsed.TotalMilliseconds,
                    SlowRequestThreshold.TotalMilliseconds);
            }
            else
            {
                logger.LogInformation(
                    "Handled {RequestName} successfully in {ElapsedMs}ms",
                    RequestName,
                    elapsed.TotalMilliseconds);
            }

            return response;
        }
        catch (Exception ex)
        {
            stopwatch.Stop();

            logger.LogError(
                ex,
                "Error handling {RequestName} after {ElapsedMs}ms",
                RequestName,
                stopwatch.Elapsed.TotalMilliseconds);

            throw;
        }
    }
}
```

### Registration

```csharp
builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssemblyContaining<Program>();
    cfg.AddBehavior(typeof(IPipelineBehavior<,>), typeof(RequestLoggingBehavior<,>));
});
```

## Pattern 5: Health Checks

### Basic Configuration

```csharp
// Program.cs
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>(
        name: "database",
        tags: new[] { "db", "critical" })
    .AddCheck<EmailServiceHealthCheck>(
        name: "email-service",
        tags: new[] { "external", "email" })
    .AddRedis(
        name: "redis",
        tags: new[] { "cache", "distributed" });

var app = builder.Build();

// Simple health endpoint
app.MapHealthChecks("/up");

// Detailed health with authentication
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = HealthCheckResponseWriter.WriteResponse,
    AllowCachingResponses = false
}).RequireAuthorization("HealthCheckPolicy");
```

### Custom Health Check

```csharp
public class EmailServiceHealthCheck(IEmailServiceAgent emailService) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var canConnect = await emailService.PingAsync(cancellationToken);
            
            if (canConnect)
            {
                return HealthCheckResult.Healthy("Email service is accessible");
            }
            
            return HealthCheckResult.Unhealthy("Cannot connect to email service");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy(
                "Email service health check failed", ex);
        }
    }
}
```

### Custom Response Writer

```csharp
public static class HealthCheckResponseWriter
{
    public static Task WriteResponse(
        HttpContext context, 
        HealthReport report)
    {
        context.Response.ContentType = "application/json";

        var response = new
        {
            Status = report.Status.ToString(),
            TotalDuration = report.TotalDuration.TotalMilliseconds,
            Checks = report.Entries.Select(e => new
            {
                Name = e.Key,
                Status = e.Value.Status.ToString(),
                Duration = e.Value.Duration.TotalMilliseconds,
                Exception = e.Value.Exception?.Message,
                Data = e.Value.Data
            })
        };

        return context.Response.WriteAsJsonAsync(response);
    }
}
```

## Pattern 6: LoggerMessage Pattern (High Performance)

For hot paths, use compile-time logging to avoid string interpolation overhead.

```csharp
public static partial class LoggerMessages
{
    // Information
    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Information,
        Message = "User {UserId} signed up successfully")]
    public static partial void UserSignedUp(ILogger logger, string userId);

    // Warning
    [LoggerMessage(
        EventId = 2001,
        Level = LogLevel.Warning,
        Message = "Slow database query detected: {QueryName} took {ElapsedMs}ms")]
    public static partial void SlowQueryDetected(
        ILogger logger, string queryName, long elapsedMs);

    // Error
    [LoggerMessage(
        EventId = 3001,
        Level = LogLevel.Error,
        Message = "Failed to send email to {EmailAddress}")]
    public static partial void EmailSendFailed(
        ILogger logger, Exception ex, string emailAddress);

    // With scopes
    [LoggerMessage(
        EventId = 1002,
        Level = LogLevel.Information,
        Message = "Order {OrderId} processed")]
    public static partial void OrderProcessed(ILogger logger, Guid orderId);
}

// Usage
public class SignUpHandler(ILogger<SignUpHandler> logger)
{
    public async Task<SignUpResponse> Handle(SignUpRequest request)
    {
        // ... process signup ...
        
        LoggerMessages.UserSignedUp(logger, user.Id);
        
        return new SignUpResponse { Success = true };
    }
}
```

## Pattern 7: OpenTelemetry Integration

### Configuration

```csharp
// NuGet: OpenTelemetry.Extensions.Hosting, OpenTelemetry.Instrumentation.AspNetCore

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing =>
    {
        tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddEntityFrameworkCoreInstrumentation()
            .AddSource("MyApp") // Custom activity source
            .AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri("http://localhost:4317");
            });
    })
    .WithMetrics(metrics =>
    {
        metrics
            .AddAspNetCoreInstrumentation()
            .AddRuntimeInstrumentation()
            .AddPrometheusExporter();
    });

var app = builder.Build();
app.UseOpenTelemetryPrometheusScrapingEndpoint();
```

### Custom Activities

```csharp
public class OrderProcessingService
{
    private static readonly ActivitySource ActivitySource = new("MyApp.Orders");

    public async Task ProcessOrderAsync(Order order)
    {
        using var activity = ActivitySource.StartActivity("ProcessOrder");
        activity?.SetTag("order.id", order.Id);
        activity?.SetTag("order.total", order.Total);

        try
        {
            activity?.AddEvent(new ActivityEvent("ValidatingOrder"));
            await ValidateOrderAsync(order);

            activity?.AddEvent(new ActivityEvent("ChargingPayment"));
            await ChargePaymentAsync(order);

            activity?.AddEvent(new ActivityEvent("SendingConfirmation"));
            await SendConfirmationAsync(order);

            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }
}
```

## Pattern 8: Razor Pages Error Logging

```csharp
[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
[IgnoreAntiforgeryToken]
public class ErrorModel(ILogger<ErrorModel> logger) : PageModel
{
    public string? RequestId { get; set; }
    public bool ShowRequestId => !string.IsNullOrEmpty(RequestId);
    public string? ErrorMessage { get; set; }

    public void OnGet()
    {
        RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier;
        
        // Log the error that brought us here
        var exceptionHandlerPathFeature = HttpContext.Features.Get<IExceptionHandlerPathFeature>();
        
        if (exceptionHandlerPathFeature?.Error != null)
        {
            var ex = exceptionHandlerPathFeature.Error;
            var path = exceptionHandlerPathFeature.Path;
            
            logger.LogError(ex, 
                "Unhandled exception at {Path}. RequestId: {RequestId}", 
                path, RequestId);
            
            // Only show details in development
            if (HttpContext.RequestServices.GetRequiredService<IWebHostEnvironment>().IsDevelopment())
            {
                ErrorMessage = ex.ToString();
            }
        }
    }
}
```

## Anti-Patterns

### Static Logger Access

```csharp
// ❌ BAD: Static logger access
public class OrderService
{
    private static readonly Logger Logger = Log.ForContext<OrderService>();
}

// ✅ GOOD: Inject ILogger<T>
public class OrderService(ILogger<OrderService> logger)
{
}
```

### String Interpolation in Logs

```csharp
// ❌ BAD: String interpolation evaluated even if log level is disabled
_logger.LogInformation($"Processing order {orderId} for user {userId}");

// ✅ GOOD: Structured logging with parameters
_logger.LogInformation("Processing order {OrderId} for user {UserId}", orderId, userId);

// ✅ BETTER: Use LoggerMessage for hot paths
[LoggerMessage(EventId = 1001, Level = LogLevel.Information, Message = "Processing order {OrderId} for user {UserId}")]
public static partial void ProcessingOrder(ILogger logger, Guid orderId, string userId);
```

### Catching and Swallowing Exceptions

```csharp
// ❌ BAD: Silent failures
try
{
    await _service.DoWorkAsync();
}
catch (Exception ex)
{
    // Nothing logged!
}

// ✅ GOOD: Always log exceptions
catch (Exception ex)
{
    _logger.LogError(ex, "Failed to complete work");
    throw; // Re-throw if you can't handle it
}
```

## References

- Serilog: https://serilog.net/
- Serilog.AspNetCore: https://github.com/serilog/serilog-aspnetcore
- Health Checks: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks
- OpenTelemetry: https://opentelemetry.io/docs/instrumentation/net/
- LoggerMessage Source Generator: https://learn.microsoft.com/en-us/dotnet/core/extensions/logger-message-generator
