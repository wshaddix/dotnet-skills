---
name: middleware-patterns
description: Custom middleware patterns for ASP.NET Core Razor Pages applications. Covers request/response pipeline, middleware ordering, conditional middleware, and reusable middleware components.
version: 1.0
last-updated: 2026-02-11
tags: [aspnetcore, middleware, pipeline, razor-pages, request-response]
---

You are a senior ASP.NET Core architect specializing in middleware development. When building custom middleware for Razor Pages applications, apply these patterns to create reusable, testable, and well-ordered pipeline components. Target .NET 8+ with nullable reference types enabled.

## Rationale

Middleware is the backbone of ASP.NET Core request processing. Properly designed middleware enables cross-cutting concerns like logging, authentication, and caching. Understanding the pipeline order and middleware patterns is critical for building robust applications.

## Middleware Pipeline Order

The order of middleware registration matters significantly:

```
1. Exception Handler (catches all errors)
2. HTTPS Redirection (before any sensitive data)
3. Static Files (short-circuits pipeline for files)
4. Routing (determines endpoint)
5. Authentication (who are you?)
6. Authorization (what can you do?)
7. Custom Middleware (operates on authenticated requests)
8. Endpoints (Razor Pages, API controllers)
```

## Pattern 1: Basic Middleware Structure

```csharp
public class RequestTimingMiddleware(RequestDelegate next, ILogger<RequestTimingMiddleware> logger)
{
    public async Task Invoke(HttpContext context)
    {
        var stopwatch = Stopwatch.StartNew();
        logger.LogInformation("Request {Method} {Path} started", 
            context.Request.Method, 
            context.Request.Path);

        try
        {
            await next(context);
        }
        finally
        {
            stopwatch.Stop();
            logger.LogInformation(
                "Request {Method} {Path} completed in {ElapsedMs}ms - Status {StatusCode}",
                context.Request.Method,
                context.Request.Path,
                stopwatch.ElapsedMilliseconds,
                context.Response.StatusCode);
        }
    }
}

// Extension method for clean registration
public static class RequestTimingExtensions
{
    public static IApplicationBuilder UseRequestTiming(this IApplicationBuilder app)
    {
        return app.UseMiddleware<RequestTimingMiddleware>();
    }
}

// Usage in Program.cs
var app = builder.Build();
app.UseRequestTiming();
```

## Pattern 2: Convention-Based Middleware

ASP.NET Core 8+ supports convention-based middleware with minimal code.

```csharp
public class ApiKeyMiddleware(RequestDelegate next, IConfiguration config)
{
    private const string ApiKeyHeader = "X-API-Key";
    
    public async Task Invoke(HttpContext context)
    {
        if (!context.Request.Headers.TryGetValue(ApiKeyHeader, out var apiKey))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsync("API Key is missing");
            return;
        }

        var validKey = config["ApiKey"];
        if (apiKey != validKey)
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsync("Invalid API Key");
            return;
        }

        await next(context);
    }
}

// Inline middleware (for simple cases)
app.Use(async (context, next) =>
{
    // Before request
    logger.LogInformation("Processing request...");
    
    await next();
    
    // After request
    logger.LogInformation("Request processed with status {Status}", 
        context.Response.StatusCode);
});
```

## Pattern 3: Conditional Middleware

Apply middleware only to specific routes or conditions.

```csharp
public class MaintenanceModeMiddleware(RequestDelegate next, IConfiguration config)
{
    public async Task Invoke(HttpContext context)
    {
        var isMaintenanceMode = config.GetValue<bool>("MaintenanceMode:Enabled");
        var allowedIps = config.GetSection("MaintenanceMode:AllowedIps").Get<string[]>() ?? Array.Empty<string>();
        var requestIp = context.Connection.RemoteIpAddress?.ToString();

        if (isMaintenanceMode && !allowedIps.Contains(requestIp))
        {
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            context.Response.Headers["Retry-After"] = "3600";
            await context.Response.WriteAsync("Service is under maintenance");
            return;
        }

        await next(context);
    }
}

// Conditional registration using MapWhen
app.MapWhen(
    context => context.Request.Path.StartsWithSegments("/api"),
    apiApp =>
    {
        apiApp.UseApiKeyValidation();
        apiApp.UseRateLimiting();
    });

// Conditional registration using UseWhen (rejoins main pipeline)
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/admin"),
    adminApp =>
    {
        adminApp.UseMiddleware<AdminAuditMiddleware>();
    });
```

## Pattern 4: Branching Middleware

Create completely separate pipelines for different route prefixes.

```csharp
// Branch for API routes
app.Map("/api", apiApp =>
{
    apiApp.UseExceptionHandler("/api/error");
    apiApp.UseHttpsRedirection();
    apiApp.UseAuthentication();
    apiApp.UseAuthorization();
    apiApp.UseRateLimiter();
    apiApp.MapControllers();
});

// Branch for webhook routes (different auth)
app.Map("/webhooks", webhookApp =>
{
    webhookApp.UseMiddleware<WebhookSignatureValidation>();
    webhookApp.UseMiddleware<WebhookIdempotency>();
    webhookApp.MapRazorPages();
});

// Main application pipeline
app.UseExceptionHandler("/Error");
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();
```

## Pattern 5: Request/Response Interception

Middleware can intercept and modify both requests and responses.

```csharp
public class ResponseCompressionMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context)
    {
        var originalBody = context.Response.Body;

        try
        {
            using var memoryStream = new MemoryStream();
            context.Response.Body = memoryStream;

            await next(context);

            // Check if client accepts compression
            if (context.Request.Headers.AcceptEncoding.Contains("gzip") &&
                ShouldCompress(context.Response.ContentType))
            {
                context.Response.Headers.ContentEncoding = "gzip";
                
                memoryStream.Position = 0;
                await using var compressedStream = new GZipStream(originalBody, CompressionMode.Compress);
                await memoryStream.CopyToAsync(compressedStream);
            }
            else
            {
                memoryStream.Position = 0;
                await memoryStream.CopyToAsync(originalBody);
            }
        }
        finally
        {
            context.Response.Body = originalBody;
        }
    }

    private static bool ShouldCompress(string? contentType)
    {
        if (string.IsNullOrEmpty(contentType)) return false;
        
        return contentType.Contains("text/") ||
               contentType.Contains("application/json") ||
               contentType.Contains("application/javascript") ||
               contentType.Contains("application/xml");
    }
}
```

## Pattern 6: Middleware with Options

Pass configuration to middleware via Options pattern.

```csharp
public class RateLimitingMiddlewareOptions
{
    public int MaxRequestsPerSecond { get; set; } = 10;
    public int BurstSize { get; set; } = 20;
    public TimeSpan BlockDuration { get; set; } = TimeSpan.FromMinutes(1);
}

public class RateLimitingMiddleware(RequestDelegate next, IOptions<RateLimitingMiddlewareOptions> options, IMemoryCache cache)
{
    private readonly RateLimitingMiddlewareOptions _options = options.Value;

    public async Task Invoke(HttpContext context)
    {
        var clientId = GetClientIdentifier(context);
        var cacheKey = $"ratelimit:{clientId}";

        if (!await TryAcquireTokenAsync(cacheKey))
        {
            context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
            context.Response.Headers.RetryAfter = _options.BlockDuration.TotalSeconds.ToString();
            await context.Response.WriteAsync("Rate limit exceeded");
            return;
        }

        await next(context);
    }

    private string GetClientIdentifier(HttpContext context)
    {
        return context.User.Identity?.Name ?? 
               context.Connection.RemoteIpAddress?.ToString() ?? 
               "anonymous";
    }

    private async Task<bool> TryAcquireTokenAsync(string cacheKey)
    {
        // Token bucket algorithm implementation
        // ... implementation details
        return true;
    }
}

// Registration with options
builder.Services.Configure<RateLimitingMiddlewareOptions>(options =>
{
    options.MaxRequestsPerSecond = 5;
    options.BurstSize = 10;
});

app.UseMiddleware<RateLimitingMiddleware>();
```

## Pattern 7: Middleware Ordering Helper

Create an extension method that enforces proper middleware order.

```csharp
public static class MiddlewarePipelineExtensions
{
    public static IApplicationBuilder UseStandardPipeline(this IApplicationBuilder app, IWebHostEnvironment env)
    {
        // 1. Exception handling (first to catch all errors)
        if (env.IsDevelopment())
        {
            app.UseDeveloperExceptionPage();
        }
        else
        {
            app.UseExceptionHandler("/Error");
            app.UseHsts();
        }

        // 2. Security headers (before any content)
        app.UseSecurityHeaders();

        // 3. HTTPS redirection
        app.UseHttpsRedirection();

        // 4. Static files (may short-circuit)
        app.UseStaticFiles();

        // 5. Routing
        app.UseRouting();

        // 6. Request logging with correlation
        app.UseRequestContextLogging();

        // 7. Authentication
        app.UseAuthentication();

        // 8. Authorization
        app.UseAuthorization();

        // 9. Custom middleware (after auth)
        app.UseRequestTiming();

        // 10. Endpoints (last)
        app.UseEndpoints(endpoints =>
        {
            endpoints.MapRazorPages();
            endpoints.MapHealthChecks("/up");
        });

        return app;
    }
}

// Usage
var app = builder.Build();
app.UseStandardPipeline(builder.Environment);
```

## Pattern 8: Middleware Testing

Test middleware components in isolation.

```csharp
public class MiddlewareTests
{
    [Fact]
    public async Task SecurityHeadersMiddleware_AddsRequiredHeaders()
    {
        // Arrange
        var middleware = new SecurityHeadersMiddleware(async (context) =>
        {
            // Simulate next middleware
            await Task.CompletedTask;
        });

        var context = new DefaultHttpContext();

        // Act
        await middleware.Invoke(context);

        // Assert
        Assert.Equal("nosniff", context.Response.Headers["X-Content-Type-Options"].ToString());
        Assert.Equal("DENY", context.Response.Headers["X-Frame-Options"].ToString());
    }

    [Fact]
    public async Task ApiKeyMiddleware_Returns401_WhenKeyMissing()
    {
        // Arrange
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new[] { new KeyValuePair<string, string?>("ApiKey", "test-key") })
            .Build();

        var middleware = new ApiKeyMiddleware(async (context) =>
        {
            await Task.CompletedTask;
        }, config);

        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        // Act
        await middleware.Invoke(context);

        // Assert
        Assert.Equal(401, context.Response.StatusCode);
    }
}
```

## Pattern 9: Endpoint-Specific Middleware

Apply middleware only to specific endpoints.

```csharp
// Using endpoint filters (Razor Pages .NET 8+)
app.MapRazorPages()
   .AddEndpointFilter(async (context, next) =>
   {
       // Runs for all Razor Pages
       logger.LogInformation("Executing Razor Page: {Page}", 
           context.HttpContext.Request.Path);
       
       return await next(context);
   });

// Conditional endpoint filters
public class AdminOnlyFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        if (!context.HttpContext.User.IsInRole("Admin"))
        {
            return Results.Forbid();
        }

        return await next(context);
    }
}

// Usage
app.MapGet("/admin/dashboard", () => Results.Ok())
   .AddEndpointFilter<AdminOnlyFilter>();
```

## Pattern 10: Middleware Factory Pattern

For middleware that needs scoped services, use IMiddleware.

```csharp
public class TransactionMiddleware : IMiddleware
{
    private readonly AppDbContext _dbContext;
    private readonly ILogger<TransactionMiddleware> _logger;

    public TransactionMiddleware(AppDbContext dbContext, ILogger<TransactionMiddleware> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context, RequestDelegate next)
    {
        await using var transaction = await _dbContext.Database.BeginTransactionAsync();

        try
        {
            await next(context);
            
            if (context.Response.StatusCode < 400)
            {
                await transaction.CommitAsync();
            }
            else
            {
                await transaction.RollbackAsync();
            }
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }
}

// Registration (required for IMiddleware)
builder.Services.AddScoped<TransactionMiddleware>();
app.UseMiddleware<TransactionMiddleware>();
```

## Anti-Patterns

### Calling Next After Response Started

```csharp
// ❌ BAD: Calling next after response has started
public async Task Invoke(HttpContext context)
{
    await context.Response.WriteAsync("Before");
    await next(context); // May fail or cause issues
    await context.Response.WriteAsync("After"); // Won't work
}

// ✅ GOOD: Only modify response before calling next
public async Task Invoke(HttpContext context)
{
    // Setup before
    var originalBody = context.Response.Body;
    context.Response.Body = new MemoryStream();
    
    await next(context);
    
    // Process after
    context.Response.Body.Position = 0;
    // ... process body ...
}
```

### Not Restoring Context

```csharp
// ❌ BAD: Not restoring HttpContext state
public async Task Invoke(HttpContext context)
{
    var originalUser = context.User;
    context.User = new ClaimsPrincipal(); // Temporarily change user
    
    await next(context);
    
    // Missing: context.User = originalUser;
}

// ✅ GOOD: Always restore state
public async Task Invoke(HttpContext context)
{
    var originalUser = context.User;
    try
    {
        context.User = new ClaimsPrincipal();
        await next(context);
    }
    finally
    {
        context.User = originalUser;
    }
}
```

### Long-Running Operations in Middleware

```csharp
// ❌ BAD: Blocking the pipeline
public async Task Invoke(HttpContext context)
{
    var data = await _service.FetchDataAsync(); // 30 seconds!
    context.Items["Data"] = data;
    await next(context);
}

// ✅ GOOD: Move long operations to background or endpoint
public async Task Invoke(HttpContext context)
{
    // Quick validation only
    if (!context.Request.Headers.ContainsKey("X-Required-Header"))
    {
        context.Response.StatusCode = 400;
        return;
    }
    
    await next(context);
}
```

## References

- ASP.NET Core Middleware: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/
- Middleware Ordering: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/
- Factory-Based Middleware: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/extensibility
