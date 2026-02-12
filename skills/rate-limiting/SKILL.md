---
name: rate-limiting
description: Rate limiting patterns for ASP.NET Core Razor Pages applications. Covers fixed window, sliding window, token bucket algorithms, and distributed rate limiting with Redis. Use when implementing rate limiting in ASP.NET Core applications, choosing between different rate limiting algorithms, or setting up distributed rate limiting with Redis.
---

## Rationale

Rate limiting protects applications from abuse, ensures fair resource usage, and prevents cascading failures during traffic spikes. Without proper rate limiting, APIs can be overwhelmed by malicious or accidental high-volume requests, leading to degraded performance or outages. These patterns provide production-ready approaches to request throttling in ASP.NET Core applications.

## Patterns

### Pattern 1: Built-in Rate Limiting Middleware (.NET 7+)

Use the built-in `Microsoft.AspNetCore.RateLimiting` middleware for common scenarios.

```csharp
// Program.cs - Basic rate limiting configuration
builder.Services.AddRateLimiter(options =>
{
    // Global rate limit for all requests
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(
        httpContext =>
        {
            var clientId = httpContext.User.Identity?.Name ?? 
                          httpContext.Connection.RemoteIpAddress?.ToString() ?? 
                          "anonymous";
            
            return RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: clientId,
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 100,
                    Window = TimeSpan.FromMinutes(1),
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit = 2
                });
        });

    // Named policies for different endpoints
    options.AddFixedWindowLimiter("login", opt =>
    {
        opt.PermitLimit = 5;
        opt.Window = TimeSpan.FromMinutes(5);
        opt.QueueLimit = 0; // Don't queue login requests
    });

    options.AddFixedWindowLimiter("api", opt =>
    {
        opt.PermitLimit = 1000;
        opt.Window = TimeSpan.FromMinutes(1);
    });

    options.AddSlidingWindowLimiter("strict", opt =>
    {
        opt.PermitLimit = 10;
        opt.Window = TimeSpan.FromSeconds(10);
        opt.SegmentsPerWindow = 2;
    });

    options.AddTokenBucketLimiter("burst", opt =>
    {
        opt.TokenLimit = 100;
        opt.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        opt.QueueLimit = 5;
        opt.ReplenishmentPeriod = TimeSpan.FromSeconds(10);
        opt.TokensPerPeriod = 20;
        opt.AutoReplenishment = true;
    });

    options.AddConcurrencyLimiter("concurrent", opt =>
    {
        opt.PermitLimit = 10;
        opt.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        opt.QueueLimit = 5;
    });

    // Custom rejection response
    options.OnRejected = async (context, token) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.Headers.Append("Retry-After", "60");
        
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            Error = "Rate limit exceeded. Please try again later.",
            RetryAfter = 60
        }, token);
    };
});

// Middleware placement (must be after UseRouting, before UseEndpoints)
var app = builder.Build();
app.UseRouting();
app.UseRateLimiter(); // Enable rate limiting
app.MapControllers();
app.MapRazorPages();
```

### Pattern 2: Per-Endpoint Rate Limiting

Apply different rate limits to different endpoints using attributes or endpoint configuration.

```csharp
// Using EnableRateLimiting attribute on controllers
[ApiController]
[Route("api/[controller]")]
[EnableRateLimiting("api")] // Use named policy
public class ProductsController : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        // Limited by "api" policy (1000 requests/minute)
        return Ok();
    }

    [HttpPost]
    [EnableRateLimiting("strict")] // Override with stricter policy
    public async Task<IActionResult> Create([FromBody] ProductDto dto)
    {
        // Limited by "strict" policy (10 requests/10 seconds)
        return Created();
    }
}

// Razor Pages with rate limiting
public class LoginModel : PageModel
{
    // Page is rate limited via attribute
    [RateLimitPolicy("login")]
    public async Task<IActionResult> OnPostAsync()
    {
        // Login logic - protected by login policy (5 attempts per 5 minutes)
    }
}

// Endpoint-specific configuration in Program.cs
app.MapPost("/api/login", async (LoginRequest request) =>
{
    // Login logic
})
.AddEndpointFilter<RateLimitEndpointFilter>()
.RequireRateLimiting("login");

// Disable rate limiting for specific endpoints
app.MapGet("/health", () => Results.Ok())
    .DisableRateLimiting();
```

### Pattern 3: Redis-Based Distributed Rate Limiting

Use Redis for rate limiting in distributed/multi-server environments.

```csharp
// Redis rate limiting configuration
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(
        httpContext =>
        {
            var clientId = GetClientIdentifier(httpContext);
            
            return RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: clientId,
                factory: partitionKey => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 100,
                    Window = TimeSpan.FromMinutes(1)
                });
        });
});

// Custom distributed rate limiter using Redis
public class RedisRateLimiter : IRateLimiter
{
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisRateLimiter> _logger;

    public RedisRateLimiter(IConnectionMultiplexer redis, ILogger<RedisRateLimiter> logger)
    {
        _redis = redis;
        _logger = logger;
    }

    public async Task<RateLimitResult> CheckLimitAsync(
        string key, 
        int limit, 
        TimeSpan window)
    {
        var db = _redis.GetDatabase();
        var redisKey = $"ratelimit:{key}";
        
        // Lua script for atomic check-and-increment
        var script = @"
            local current = redis.call('GET', KEYS[1])
            if current == false then
                current = 0
            end
            if tonumber(current) < tonumber(ARGV[1]) then
                redis.call('INCR', KEYS[1])
                redis.call('EXPIRE', KEYS[1], ARGV[2])
                return {1, tonumber(current) + 1, tonumber(ARGV[1])}
            else
                local ttl = redis.call('TTL', KEYS[1])
                return {0, tonumber(current), tonumber(ARGV[1]), ttl}
            end";

        var result = await db.ScriptEvaluateAsync(script,
            new RedisKey[] { redisKey },
            new RedisValue[] { limit, window.TotalSeconds });

        var values = (RedisResult[])result!;
        var allowed = (bool)values[0];
        var current = (int)values[1];
        var limitValue = (int)values[2];
        var retryAfter = allowed ? 0 : (int)values[3];

        return new RateLimitResult(
            Allowed: allowed,
            Current: current,
            Limit: limitValue,
            RetryAfter: retryAfter);
    }
}

public record RateLimitResult(bool Allowed, int Current, int Limit, int RetryAfter);

// Custom rate limiting middleware
public class DistributedRateLimitMiddleware
{
    private readonly RequestDelegate _next;
    private readonly RedisRateLimiter _rateLimiter;
    private readonly ILogger<DistributedRateLimitMiddleware> _logger;

    public DistributedRateLimitMiddleware(
        RequestDelegate next,
        RedisRateLimiter rateLimiter,
        ILogger<DistributedRateLimitMiddleware> logger)
    {
        _next = next;
        _rateLimiter = rateLimiter;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var clientId = GetClientIdentifier(context);
        var path = context.Request.Path.Value ?? "";
        
        // Different limits for different paths
        var (limit, window) = GetLimitForPath(path);
        
        var result = await _rateLimiter.CheckLimitAsync(
            $"{clientId}:{path}", 
            limit, 
            window);

        // Add rate limit headers
        AddRateLimitHeaders(context.Response, result);

        if (!result.Allowed)
        {
            _logger.LogWarning(
                "Rate limit exceeded for {ClientId} on {Path}",
                clientId, path);

            context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
            context.Response.Headers.Append("Retry-After", result.RetryAfter.ToString());
            
            await context.Response.WriteAsJsonAsync(new
            {
                Error = "Rate limit exceeded",
                RetryAfter = result.RetryAfter,
                Limit = result.Limit,
                Window = window.TotalSeconds
            });
            
            return;
        }

        await _next(context);
    }

    private static (int Limit, TimeSpan Window) GetLimitForPath(string path)
    {
        if (path.StartsWith("/api/login"))
            return (5, TimeSpan.FromMinutes(5));
        if (path.StartsWith("/api/"))
            return (1000, TimeSpan.FromMinutes(1));
        
        return (100, TimeSpan.FromMinutes(1));
    }

    private static void AddRateLimitHeaders(HttpResponse response, RateLimitResult result)
    {
        response.Headers.Append("X-RateLimit-Limit", result.Limit.ToString());
        response.Headers.Append("X-RateLimit-Remaining", (result.Limit - result.Current).ToString());
    }
}
```

### Pattern 4: User-Based Rate Limiting

Implement rate limiting based on authenticated user identity.

```csharp
// User-based rate limiter
public class UserBasedRateLimiter
{
    private readonly IRateLimiter _rateLimiter;
    private readonly IUserService _userService;

    public UserBasedRateLimiter(IRateLimiter rateLimiter, IUserService userService)
    {
        _rateLimiter = rateLimiter;
        _userService = userService;
    }

    public async Task<bool> CheckUserLimitAsync(HttpContext context)
    {
        var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        
        if (string.IsNullOrEmpty(userId))
        {
            // Fall back to IP-based limiting for anonymous users
            return await CheckAnonymousLimitAsync(context);
        }

        // Get user's subscription tier
        var user = await _userService.GetUserAsync(userId);
        var (limit, window) = GetLimitForTier(user?.SubscriptionTier);

        var key = $"user:{userId}";
        var result = await _rateLimiter.CheckLimitAsync(key, limit, window);

        AddRateLimitHeaders(context.Response, result);
        
        return result.Allowed;
    }

    private async Task<bool> CheckAnonymousLimitAsync(HttpContext context)
    {
        var ipAddress = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        var key = $"ip:{ipAddress}";
        
        // Stricter limits for anonymous users
        var result = await _rateLimiter.CheckLimitAsync(key, 30, TimeSpan.FromMinutes(1));
        
        AddRateLimitHeaders(context.Response, result);
        
        return result.Allowed;
    }

    private static (int Limit, TimeSpan Window) GetLimitForTier(SubscriptionTier? tier)
    {
        return tier switch
        {
            SubscriptionTier.Enterprise => (10000, TimeSpan.FromMinutes(1)),
            SubscriptionTier.Pro => (1000, TimeSpan.FromMinutes(1)),
            SubscriptionTier.Basic => (100, TimeSpan.FromMinutes(1)),
            _ => (50, TimeSpan.FromMinutes(1)) // Free tier
        };
    }
}

// Middleware integration
public class UserRateLimitMiddleware
{
    private readonly RequestDelegate _next;
    private readonly UserBasedRateLimiter _rateLimiter;

    public UserRateLimitMiddleware(RequestDelegate next, UserBasedRateLimiter rateLimiter)
    {
        _next = next;
        _rateLimiter = rateLimiter;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!await _rateLimiter.CheckUserLimitAsync(context))
        {
            context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
            await context.Response.WriteAsJsonAsync(new
            {
                Error = "Rate limit exceeded",
                UpgradeUrl = "/pricing"
            });
            return;
        }

        await _next(context);
    }
}

// Razor Page with tier-based limiting
public class ApiDashboardModel : PageModel
{
    private readonly IUserRateLimitService _rateLimitService;

    public int CurrentUsage { get; set; }
    public int MonthlyLimit { get; set; }

    public async Task OnGetAsync()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        
        var usage = await _rateLimitService.GetMonthlyUsageAsync(userId);
        CurrentUsage = usage.Current;
        MonthlyLimit = usage.Limit;
    }
}
```

### Pattern 5: Rate Limiting with Client Identification

Handle various client identification scenarios including proxies and load balancers.

```csharp
public static class ClientIdentifierHelper
{
    public static string GetClientIdentifier(HttpContext context)
    {
        // 1. Try authenticated user first
        var userId = context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (!string.IsNullOrEmpty(userId))
        {
            return $"user:{userId}";
        }

        // 2. Try API key
        var apiKey = context.Request.Headers["X-API-Key"].FirstOrDefault();
        if (!string.IsNullOrEmpty(apiKey))
        {
            return $"apikey:{apiKey}";
        }

        // 3. Get IP address (handling proxies)
        var ip = GetClientIpAddress(context);
        return $"ip:{ip}";
    }

    public static string GetClientIpAddress(HttpContext context)
    {
        // Check X-Forwarded-For header (when behind load balancer/proxy)
        var forwardedFor = context.Request.Headers["X-Forwarded-For"].FirstOrDefault();
        if (!string.IsNullOrEmpty(forwardedFor))
        {
            // Take the first IP if multiple are present
            var ips = forwardedFor.Split(',', StringSplitOptions.RemoveEmptyEntries);
            if (ips.Length > 0)
            {
                return ips[0].Trim();
            }
        }

        // Check X-Real-IP header
        var realIp = context.Request.Headers["X-Real-IP"].FirstOrDefault();
        if (!string.IsNullOrEmpty(realIp))
        {
            return realIp;
        }

        // Fall back to connection IP
        return context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    }

    public static bool IsTrustedProxy(HttpContext context, IEnumerable<string> trustedProxies)
    {
        var remoteIp = context.Connection.RemoteIpAddress;
        return remoteIp != null && trustedProxies.Any(proxy =>
        {
            if (IPAddress.TryParse(proxy, out var trustedIp))
            {
                return remoteIp.Equals(trustedIp);
            }
            return false;
        });
    }
}

// Configuration for forwarded headers (Program.cs)
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// Use forwarded headers middleware
app.UseForwardedHeaders();
```

## Anti-Patterns

```csharp
// ❌ BAD: Same limits for all endpoints
options.AddFixedWindowLimiter("default", opt =>
{
    opt.PermitLimit = 100;
    opt.Window = TimeSpan.FromMinutes(1);
});
// Applied to everything - login endpoints need stricter limits!

// ✅ GOOD: Different policies for different endpoints
options.AddFixedWindowLimiter("login", opt =>
{
    opt.PermitLimit = 5; // Strict for authentication
    opt.Window = TimeSpan.FromMinutes(5);
});

options.AddFixedWindowLimiter("api", opt =>
{
    opt.PermitLimit = 1000; // Generous for API
    opt.Window = TimeSpan.FromMinutes(1);
});

// ❌ BAD: No headers indicating rate limit status
// Clients can't track their usage

// ✅ GOOD: Include rate limit headers
context.Response.Headers.Append("X-RateLimit-Limit", limit.ToString());
context.Response.Headers.Append("X-RateLimit-Remaining", remaining.ToString());
context.Response.Headers.Append("X-RateLimit-Reset", resetTime.ToString());

// ❌ BAD: Wrong middleware order
app.UseRateLimiter();
app.UseAuthentication();
// Can't identify users if auth hasn't run yet!

// ✅ GOOD: Rate limiter after authentication
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

// ❌ BAD: Not handling rate limit in-memory only
// Won't work across multiple servers
var limiter = new FixedWindowRateLimiter(new FixedWindowRateLimiterOptions
{
    PermitLimit = 100,
    Window = TimeSpan.FromMinutes(1)
});

// ✅ GOOD: Use distributed storage for multi-server
typeof(DistributedCacheRateLimiter)

// ❌ BAD: No fallback when rate limiter fails
public async Task<bool> CheckLimit(string key)
{
    var result = await _redis.CheckLimitAsync(key); // If Redis fails, whole app fails!
    return result.Allowed;
}

// ✅ GOOD: Graceful degradation
public async Task<bool> CheckLimit(string key)
{
    try
    {
        var result = await _redis.CheckLimitAsync(key);
        return result.Allowed;
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Rate limit check failed, allowing request");
        return true; // Fail open
    }
}

// ❌ BAD: Blocking on rate limit check
public IActionResult GetData()
{
    var allowed = CheckLimitAsync().Result; // Blocks thread!
    if (!allowed) return StatusCode(429);
    // ...
}

// ✅ GOOD: Async rate limiting
public async Task<IActionResult> GetDataAsync()
{
    var allowed = await CheckLimitAsync();
    if (!allowed) return StatusCode(429);
    // ...
}

// ❌ BAD: Logging every blocked request at Error level
// Creates log spam during attacks

// ✅ GOOD: Log at appropriate level with sampling
_logger.LogWarning("Rate limit exceeded for {ClientId}", clientId);

// Or use metrics instead
_metrics.RecordRateLimitHit(clientId);
```

## References

- [Rate Limiting in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit)
- [Rate Limiting Middleware](https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit?view=aspnetcore-7.0)
- [Partitioned Rate Limiters](https://learn.microsoft.com/en-us/dotnet/api/system.threading.ratelimiting.partitionedratelimiter-2)
- [Redis Rate Limiting](https://redis.io/commands/incr/)
- [OWASP Rate Limiting](https://cheatsheetseries.owasp.org/cheatsheets/Denial_of_Service_Cheat_Sheet.html)
