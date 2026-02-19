---
name: middleware-patterns
description: Custom middleware patterns for ASP.NET Core applications. Covers request/response pipeline, middleware ordering, conditional middleware, IMiddleware factory pattern, IExceptionHandler (.NET 8+), and reusable middleware components. Use when creating custom middleware in ASP.NET Core applications, understanding middleware pipeline ordering, or implementing cross-cutting concerns like logging, authentication, and caching.
---

# ASP.NET Core Middleware Patterns

## Rationale

Middleware is the backbone of ASP.NET Core request processing. Properly designed middleware enables cross-cutting concerns like logging, authentication, and caching. Understanding the pipeline order and middleware patterns is critical for building robust applications.

---

## Pipeline Ordering

Middleware executes in the order it is registered. The order is critical -- placing middleware in the wrong position causes subtle bugs.

### Recommended Order

```csharp
var app = builder.Build();

// 1. Exception handling (outermost -- catches everything below)
app.UseExceptionHandler("/error");

// 2. HSTS (before any response is sent)
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

// 3. HTTPS redirection
app.UseHttpsRedirection();

// 4. Static files (short-circuits for static content before routing)
app.UseStaticFiles();

// 5. Routing (matches endpoints but does not execute them yet)
app.UseRouting();

// 6. CORS (must be after routing, before auth)
app.UseCors();

// 7. Authentication (identifies the user)
app.UseAuthentication();

// 8. Authorization (checks permissions against the matched endpoint)
app.UseAuthorization();

// 9. Custom middleware (runs after auth, before endpoint execution)
app.UseRequestLogging();

// 10. Endpoint execution (terminal -- executes the matched endpoint)
app.MapControllers();
app.MapRazorPages();
```

### Why Order Matters

| Mistake | Consequence |
|---------|-------------|
| `UseAuthorization()` before `UseRouting()` | Authorization has no endpoint metadata -- all requests pass |
| `UseCors()` after `UseAuthorization()` | Preflight requests fail because they lack auth tokens |
| `UseExceptionHandler()` after custom middleware | Exceptions in custom middleware are unhandled |
| `UseStaticFiles()` after `UseAuthorization()` | Static files require authentication unnecessarily |

---

## Pattern 1: Convention-Based Middleware

Convention-based middleware uses a constructor with `RequestDelegate` and an `InvokeAsync` method.

```csharp
public sealed class RequestTimingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestTimingMiddleware> _logger;

    public RequestTimingMiddleware(
        RequestDelegate next,
        ILogger<RequestTimingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var stopwatch = Stopwatch.StartNew();

        try
        {
            await _next(context);
        }
        finally
        {
            stopwatch.Stop();
            _logger.LogInformation(
                "Request {Method} {Path} completed in {ElapsedMs}ms with status {StatusCode}",
                context.Request.Method,
                context.Request.Path,
                stopwatch.ElapsedMilliseconds,
                context.Response.StatusCode);
        }
    }
}

public static class RequestTimingMiddlewareExtensions
{
    public static IApplicationBuilder UseRequestTiming(this IApplicationBuilder app)
        => app.UseMiddleware<RequestTimingMiddleware>();
}

// Usage in Program.cs
app.UseRequestTiming();
```

---

## Pattern 2: Factory-Based (IMiddleware)

For middleware that requires scoped services, implement `IMiddleware`. This uses DI to create middleware instances per-request:

```csharp
public sealed class TenantMiddleware : IMiddleware
{
    private readonly TenantDbContext _db;

    public TenantMiddleware(TenantDbContext db)
    {
        _db = db;
    }

    public async Task InvokeAsync(HttpContext context, RequestDelegate next)
    {
        var tenantId = context.Request.Headers["X-Tenant-Id"].FirstOrDefault();

        if (tenantId is not null)
        {
            var tenant = await _db.Tenants.FindAsync(tenantId);
            context.Items["Tenant"] = tenant;
        }

        await next(context);
    }
}

// IMiddleware requires explicit DI registration
builder.Services.AddScoped<TenantMiddleware>();
app.UseMiddleware<TenantMiddleware>();
```

### Convention-Based vs IMiddleware

| Aspect | Convention-based | `IMiddleware` |
|--------|-----------------|---------------|
| Lifetime | Singleton (created once) | Per-request (from DI) |
| Scoped services | Via `InvokeAsync` parameters only | Via constructor injection |
| Registration | `UseMiddleware<T>()` only | Requires `services.Add*<T>()` + `UseMiddleware<T>()` |
| Performance | Slightly faster | Resolved from DI each request |

---

## Pattern 3: Inline Middleware

For simple, one-off logic:

### app.Use -- Pass-Through

```csharp
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Request-Id"] = context.TraceIdentifier;
    await next(context);
});
```

### app.Run -- Terminal

```csharp
app.Run(async context =>
{
    await context.Response.WriteAsync("Fallback response");
});
```

### app.Map -- Branch by Path

```csharp
app.Map("/api/diagnostics", diagnosticApp =>
{
    diagnosticApp.Run(async context =>
    {
        var data = new
        {
            MachineName = Environment.MachineName,
            Timestamp = DateTimeOffset.UtcNow
        };
        await context.Response.WriteAsJsonAsync(data);
    });
});
```

---

## Pattern 4: Short-Circuit Logic

Middleware can short-circuit the pipeline by not calling `next()`.

### Request Validation

```csharp
public sealed class ApiKeyMiddleware
{
    private readonly RequestDelegate _next;
    private readonly string _expectedKey;

    public ApiKeyMiddleware(RequestDelegate next, IConfiguration config)
    {
        _next = next;
        _expectedKey = config["ApiKey"]
            ?? throw new InvalidOperationException("ApiKey configuration is required");
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!context.Request.Headers.TryGetValue("X-Api-Key", out var providedKey)
            || !string.Equals(providedKey, _expectedKey, StringComparison.Ordinal))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new
            {
                Error = "Invalid or missing API key"
            });
            return; // Short-circuit
        }

        await _next(context);
    }
}
```

### Feature Flag Gate

```csharp
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/beta"),
    betaApp =>
    {
        betaApp.Use(async (context, next) =>
        {
            var featureManager = context.RequestServices
                .GetRequiredService<IFeatureManager>();

            if (!await featureManager.IsEnabledAsync("BetaFeatures"))
            {
                context.Response.StatusCode = StatusCodes.Status404NotFound;
                return;
            }

            await next(context);
        });
    });
```

---

## Pattern 5: Request and Response Manipulation

### Reading the Request Body

```csharp
public sealed class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        context.Request.EnableBuffering();

        if (context.Request.ContentLength > 0 && context.Request.ContentLength < 64_000)
        {
            context.Request.Body.Position = 0;
            using var reader = new StreamReader(context.Request.Body, leaveOpen: true);
            var body = await reader.ReadToEndAsync();
            _logger.LogDebug("Request body for {Path}: {Body}", context.Request.Path, body);
            context.Request.Body.Position = 0;
        }

        await _next(context);
    }
}
```

### Modifying the Response

```csharp
public async Task InvokeAsync(HttpContext context)
{
    var originalBodyStream = context.Response.Body;

    using var responseBody = new MemoryStream();
    context.Response.Body = responseBody;

    await _next(context);

    context.Response.Body.Seek(0, SeekOrigin.Begin);
    var responseText = await new StreamReader(context.Response.Body).ReadToEndAsync();
    context.Response.Body.Seek(0, SeekOrigin.Begin);

    await responseBody.CopyToAsync(originalBodyStream);
}
```

**Caution:** Response body replacement adds memory overhead. Use only for diagnostics.

---

## Pattern 6: Exception Handling Middleware

### Built-in Exception Handler

```csharp
app.UseExceptionHandler(exceptionApp =>
{
    exceptionApp.Run(async context =>
    {
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";

        var exceptionFeature = context.Features.Get<IExceptionHandlerFeature>();

        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        logger.LogError(exceptionFeature?.Error, "Unhandled exception for {Path}", context.Request.Path);

        await context.Response.WriteAsJsonAsync(new
        {
            Error = "An internal error occurred",
            TraceId = context.TraceIdentifier
        });
    });
});
```

### IExceptionHandler (.NET 8+)

Multiple handlers can be registered and are invoked in order:

```csharp
public sealed class ValidationExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context,
        Exception exception,
        CancellationToken ct)
    {
        if (exception is not ValidationException validationException)
            return false;

        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsJsonAsync(new
        {
            Error = "Validation failed",
            Details = validationException.Errors
        }, ct);

        return true;
    }
}

public sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context,
        Exception exception,
        CancellationToken ct)
    {
        logger.LogError(exception, "Unhandled exception");

        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        await context.Response.WriteAsJsonAsync(new
        {
            Error = "An internal error occurred",
            TraceId = context.TraceIdentifier
        }, ct);

        return true;
    }
}

builder.Services.AddExceptionHandler<ValidationExceptionHandler>();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

app.UseExceptionHandler();
```

### StatusCodePages for Non-Exception Errors

```csharp
app.UseStatusCodePagesWithReExecute("/error/{0}");

app.UseStatusCodePages(async context =>
{
    context.HttpContext.Response.ContentType = "application/json";
    await context.HttpContext.Response.WriteAsJsonAsync(new
    {
        Error = $"HTTP {context.HttpContext.Response.StatusCode}",
        TraceId = context.HttpContext.TraceIdentifier
    });
});
```

---

## Pattern 7: Conditional Middleware

### UseWhen -- Conditional Branch (Rejoins Pipeline)

```csharp
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/api"),
    apiApp =>
    {
        apiApp.UseRateLimiter();
    });
```

### MapWhen -- Conditional Branch (Does Not Rejoin)

```csharp
app.MapWhen(
    context => context.WebSockets.IsWebSocketRequest,
    wsApp =>
    {
        wsApp.Run(async context =>
        {
            using var ws = await context.WebSockets.AcceptWebSocketAsync();
        });
    });
```

### Environment-Specific Middleware

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    app.UseExceptionHandler("/error");
    app.UseHsts();
}
```

---

## Pattern 8: Branching Middleware

Create completely separate pipelines for different route prefixes:

```csharp
app.Map("/api", apiApp =>
{
    apiApp.UseExceptionHandler("/api/error");
    apiApp.UseHttpsRedirection();
    apiApp.UseAuthentication();
    apiApp.UseAuthorization();
    apiApp.UseRateLimiter();
    apiApp.MapControllers();
});

app.Map("/webhooks", webhookApp =>
{
    webhookApp.UseMiddleware<WebhookSignatureValidation>();
    webhookApp.UseMiddleware<WebhookIdempotency>();
    webhookApp.MapRazorPages();
});

app.UseExceptionHandler("/Error");
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();
```

---

## Pattern 9: Middleware with Options

```csharp
public class RateLimitingMiddlewareOptions
{
    public int MaxRequestsPerSecond { get; set; } = 10;
    public int BurstSize { get; set; } = 20;
    public TimeSpan BlockDuration { get; set; } = TimeSpan.FromMinutes(1);
}

public class RateLimitingMiddleware(
    RequestDelegate next,
    IOptions<RateLimitingMiddlewareOptions> options,
    IMemoryCache cache)
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

    private async Task<bool> TryAcquireTokenAsync(string cacheKey) => true;
}

builder.Services.Configure<RateLimitingMiddlewareOptions>(options =>
{
    options.MaxRequestsPerSecond = 5;
    options.BurstSize = 10;
});

app.UseMiddleware<RateLimitingMiddleware>();
```

---

## Pattern 10: Middleware Testing

```csharp
public class MiddlewareTests
{
    [Fact]
    public async Task SecurityHeadersMiddleware_AddsRequiredHeaders()
    {
        var middleware = new SecurityHeadersMiddleware(async (context) =>
        {
            await Task.CompletedTask;
        });

        var context = new DefaultHttpContext();

        await middleware.Invoke(context);

        Assert.Equal("nosniff", context.Response.Headers["X-Content-Type-Options"].ToString());
        Assert.Equal("DENY", context.Response.Headers["X-Frame-Options"].ToString());
    }

    [Fact]
    public async Task ApiKeyMiddleware_Returns401_WhenKeyMissing()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new[] { new KeyValuePair<string, string?>("ApiKey", "test-key") })
            .Build();

        var middleware = new ApiKeyMiddleware(async (context) =>
        {
            await Task.CompletedTask;
        }, config);

        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        await middleware.Invoke(context);

        Assert.Equal(401, context.Response.StatusCode);
    }
}
```

---

## Anti-Patterns

### Calling Next After Response Started

```csharp
// BAD: Calling next after response has started
public async Task Invoke(HttpContext context)
{
    await context.Response.WriteAsync("Before");
    await next(context); // May fail
    await context.Response.WriteAsync("After"); // Won't work
}

// GOOD: Only modify response before calling next
public async Task Invoke(HttpContext context)
{
    var originalBody = context.Response.Body;
    context.Response.Body = new MemoryStream();

    await next(context);

    context.Response.Body.Position = 0;
    await context.Response.Body.CopyToAsync(originalBody);
}
```

### Not Restoring Context

```csharp
// BAD: Not restoring HttpContext state
public async Task Invoke(HttpContext context)
{
    var originalUser = context.User;
    context.User = new ClaimsPrincipal();
    await next(context);
    // Missing: context.User = originalUser;
}

// GOOD: Always restore state
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

---

## Key Principles

- **Order is everything** -- middleware executes top-to-bottom for requests and bottom-to-top for responses
- **Exception handler goes first** -- `UseExceptionHandler` must be outermost
- **Prefer classes over inline for reusable middleware** -- testable, composable, single-responsibility
- **Use `IMiddleware` for scoped dependencies** -- convention-based is singleton
- **Short-circuit intentionally** -- always document why a middleware does not call `next()`
- **Avoid response body manipulation in hot paths** -- doubles memory usage per request

---

## Agent Gotchas

1. **Do not place `UseAuthorization()` before `UseRouting()`** -- authorization requires endpoint metadata.
2. **Do not place `UseCors()` after `UseAuthorization()`** -- CORS preflight requests lack auth tokens.
3. **Do not forget to call `next()` in pass-through middleware** -- silently short-circuits the pipeline.
4. **Do not read `Request.Body` without `EnableBuffering()`** -- the body is forward-only by default.
5. **Do not register `IMiddleware` without DI registration** -- requires explicit `services.AddScoped<T>()`.
6. **Do not write to `Response.Body` after calling `next()` if downstream has started response** -- check `context.Response.HasStarted`.

---

## References

- [ASP.NET Core middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/)
- [Write custom ASP.NET Core middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/write)
- [Factory-based middleware activation](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/extensibility)
- [Handle errors in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling)
- [IExceptionHandler in .NET 8](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling#iexceptionhandler)
- [Exploring ASP.NET Core (Andrew Lock)](https://andrewlock.net/)
