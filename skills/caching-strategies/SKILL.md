---
name: caching-strategies
description: Comprehensive caching patterns for ASP.NET Core Razor Pages applications. Covers output caching, response caching, memory caching, distributed caching with Redis, cache invalidation strategies, and HybridCache (.NET 9+).
version: 1.0
last-updated: 2026-02-11
tags: [aspnetcore, caching, redis, performance, razor-pages]
---

You are a senior ASP.NET Core architect specializing in caching strategies. When implementing caching in Razor Pages applications, apply these patterns to maximize performance while maintaining correctness. Target .NET 8+ with modern features and nullable reference types enabled.

## Rationale

Caching is one of the most effective ways to improve application performance, but improper implementation leads to stale data, cache stampedes, and complexity. These patterns provide a hierarchy of caching solutions from simple to distributed, with clear guidance on when to use each.

## Caching Hierarchy

| Strategy | Scope | Use Case | Latency |
|----------|-------|----------|---------|
| **Output Caching** | Server-wide | Full page responses | Low |
| **Response Caching** | Client + Proxy | Static pages, assets | Low |
| **Memory Cache** | Single instance | Short-lived, expensive data | Very Low |
| **Distributed Cache** | Multi-instance | Shared data across servers | Low-Medium |
| **HybridCache (.NET 9+)** | Multi-instance | Best of memory + distributed | Very Low |

## Pattern 1: Output Caching (Full Page)

Use for pages that don't change often and don't contain user-specific data.

### Configuration

```csharp
// Program.cs
builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(builder =>
        builder.Expire(TimeSpan.FromSeconds(10)));
    options.AddPolicy("LongCache", builder =>
        builder.Expire(TimeSpan.FromMinutes(5)));
    options.AddPolicy("AuthenticatedCache", builder =>
        builder.Expire(TimeSpan.FromMinutes(1))
               .Tag("user-specific"));
});

// Add middleware (order matters!)
var app = builder.Build();
app.UseOutputCache(); // After UseRouting, before endpoints
```

### Page-Level Usage

```csharp
// Cache entire page for 60 seconds
[OutputCache(Duration = 60)]
public class IndexModel : PageModel { }

// Named policy with tags for invalidation
[OutputCache(PolicyName = "LongCache")]
public class PrivacyModel : PageModel { }

// Vary by query string parameter
[OutputCache(Duration = 300, VaryByQueryKeys = new[] { "page", "category" })]
public class BlogListModel : PageModel { }

// Vary by header (e.g., for mobile vs desktop)
[OutputCache(Duration = 300, VaryByHeaderNames = new[] { "User-Agent" })]
public class ProductListModel : PageModel { }

// Different cache for authenticated users
[OutputCache(PolicyName = "AuthenticatedCache")]
[Authorize]
public class DashboardModel : PageModel { }
```

### Cache Invalidation

```csharp
// Tag-based invalidation
public class BlogAdminModel(IOutputCacheStore cache) : PageModel
{
    public async Task<IActionResult> OnPostPublishAsync()
    {
        // Invalidate all pages tagged with "blog"
        await cache.EvictByTagAsync("blog", CancellationToken.None);
        
        return RedirectToPage("/Blog/List");
    }
}
```

## Pattern 2: Response Caching (Client-Side)

Use for static assets and pages that can be cached by browsers and CDNs.

```csharp
// Program.cs
builder.Services.AddResponseCaching();

var app = builder.Build();
app.UseResponseCaching(); // Before UseOutputCache
```

```csharp
// Page-level cache control
[ResponseCache(Duration = 3600, Location = ResponseCacheLocation.Any)]
public class StaticContentModel : PageModel { }

// No caching (for error pages, authenticated content)
[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
public class ErrorModel : PageModel { }

// Private caching (client only, no CDN)
[ResponseCache(Duration = 60, Location = ResponseCacheLocation.Client)]
public class UserProfileModel : PageModel { }
```

## Pattern 3: Memory Caching

Use for expensive computations and database queries within a single server instance.

### Configuration

```csharp
// Program.cs
builder.Services.AddMemoryCache(options =>
{
    options.SizeLimit = 100_000_000; // 100MB total cache size
    options.CompactionPercentage = 0.25; // Remove 25% when limit reached
    options.ExpirationScanFrequency = TimeSpan.FromMinutes(5);
});
```

### Usage in Handlers/PageModels

```csharp
public class ProductService(IMemoryCache cache, AppDbContext db)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);
    
    public async Task<Product?> GetProductAsync(Guid id)
    {
        var cacheKey = $"product:{id}";
        
        if (cache.TryGetValue(cacheKey, out Product? product))
        {
            return product;
        }
        
        product = await db.Products.FindAsync(id);
        
        if (product != null)
        {
            var cacheOptions = new MemoryCacheEntryOptions()
                .SetAbsoluteExpiration(CacheDuration)
                .SetSize(1) // For size-limited cache
                .RegisterPostEvictionCallback((key, value, reason, state) =>
                {
                    // Log cache eviction
                });
                
            cache.Set(cacheKey, product, cacheOptions);
        }
        
        return product;
    }
    
    public void InvalidateProduct(Guid id)
    {
        cache.Remove($"product:{id}");
    }
}
```

### Cache-Aside Pattern with GetOrCreateAsync

```csharp
public async Task<List<Category>> GetCategoriesAsync()
{
    return await cache.GetOrCreateAsync(
        "categories:all",
        async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1);
            entry.SetSize(1);
            
            return await db.Categories
                .AsNoTracking()
                .ToListAsync();
        });
}
```

## Pattern 4: Distributed Caching (Redis)

Use for multi-instance deployments where cache must be shared.

### Configuration

```csharp
// Program.cs
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "MyApp:"; // Prefix for all keys
});

// Or using Aspire
builder.AddRedis("cache");
```

### Usage

```csharp
public class DistributedProductService(IDistributedCache cache, AppDbContext db)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);
    
    public async Task<Product?> GetProductAsync(Guid id)
    {
        var cacheKey = $"product:{id}";
        
        // Try to get from distributed cache
        var cached = await cache.GetStringAsync(cacheKey);
        if (cached != null)
        {
            return JsonSerializer.Deserialize<Product>(cached);
        }
        
        // Fetch from database
        var product = await db.Products.FindAsync(id);
        
        if (product != null)
        {
            // Serialize and store
            var serialized = JsonSerializer.Serialize(product);
            var options = new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = CacheDuration
            };
            
            await cache.SetStringAsync(cacheKey, serialized, options);
        }
        
        return product;
    }
}
```

### Sliding Expiration Pattern

```csharp
public async Task<UserSession?> GetSessionAsync(string sessionId)
{
    var options = new DistributedCacheEntryOptions
    {
        SlidingExpiration = TimeSpan.FromMinutes(20), // Extend on access
        AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(8) // Max lifetime
    };
    
    var session = await cache.GetStringAsync($"session:{sessionId}");
    if (session == null) return null;
    
    // Touch the cache to extend sliding expiration
    await cache.RefreshAsync($"session:{sessionId}");
    
    return JsonSerializer.Deserialize<UserSession>(session);
}
```

## Pattern 5: HybridCache (.NET 9+)

**Recommended for .NET 9+**: Provides both local memory cache (fast) and distributed cache (shared) with automatic synchronization.

### Configuration

```csharp
// Program.cs
builder.Services.AddHybridCache(options =>
{
    options.DefaultLocalCacheExpiration = TimeSpan.FromMinutes(5);
    options.DefaultExpiration = TimeSpan.FromMinutes(30);
    options.LocalCacheMaximumSizeBytes = 50_000_000; // 50MB
});
```

### Usage

```csharp
public class HybridProductService(IHybridCache cache, AppDbContext db)
{
    public async Task<Product?> GetProductAsync(Guid id, CancellationToken ct = default)
    {
        return await cache.GetOrCreateAsync(
            $"product:{id}",
            async cancel => await db.Products.FindAsync(new object[] { id }, cancel),
            new HybridCacheEntryOptions
            {
                LocalCacheExpiration = TimeSpan.FromMinutes(5),
                Expiration = TimeSpan.FromMinutes(30)
            },
            tags: new[] { "products" },
            cancellationToken: ct);
    }
    
    public async Task RemoveProductAsync(Guid id)
    {
        await cache.RemoveByTagAsync("products");
    }
}
```

## Cache Invalidation Strategies

### 1. Tag-Based Invalidation

```csharp
// Add tags during cache entry creation
await cache.SetAsync(key, data, options, tags: new[] { "users", $"user:{userId}" });

// Invalidate by tag
await cache.RemoveByTagAsync("users"); // Removes all user entries
```

### 2. Event-Driven Invalidation

```csharp
public class ProductUpdatedHandler(IDistributedCache cache) : INotificationHandler<ProductUpdated>
{
    public async Task Handle(ProductUpdated notification, CancellationToken ct)
    {
        await cache.RemoveAsync($"product:{notification.ProductId}");
        await cache.RemoveByTagAsync("products:list");
    }
}
```

### 3. Time-Based Invalidation

```csharp
// Different expiration strategies for different data freshness requirements
public class CachePolicies
{
    public static readonly TimeSpan UserData = TimeSpan.FromMinutes(5);
    public static readonly TimeSpan ProductData = TimeSpan.FromHours(1);
    public static readonly TimeSpan ReferenceData = TimeSpan.FromDays(1);
}
```

## Anti-Patterns

### Cache Stampede

```csharp
// ❌ BAD: Multiple requests hit database simultaneously when cache expires
public async Task<Product> GetProduct(Guid id)
{
    if (!cache.TryGetValue(id, out var product))
    {
        product = await db.Products.FindAsync(id); // All requests hit here
        cache.Set(id, product);
    }
    return product!;
}

// ✅ GOOD: Use locking to prevent stampede
public async Task<Product?> GetProductAsync(Guid id)
{
    return await cache.GetOrCreateAsync(
        $"product:{id}",
        async _ => await db.Products.FindAsync(id));
}
```

### Storing Large Objects

```csharp
// ❌ BAD: Storing entire collections
var allProducts = await db.Products.ToListAsync();
cache.Set("products:all", allProducts);

// ✅ GOOD: Store individual items, paginate
var products = await db.Products
    .Skip(offset)
    .Take(50)
    .ToListAsync();
```

### Inconsistent Cache Keys

```csharp
// ❌ BAD: Inconsistent key generation
var key1 = $"user-{userId}";
var key2 = $"user:{userId}";
var key3 = $"User:{userId}";

// ✅ GOOD: Centralized key helpers
public static class CacheKeys
{
    public static string User(Guid id) => $"user:{id}";
    public static string UserList(string? filter = null) => 
        filter == null ? "users:all" : $"users:filter:{filter}";
}
```

## Razor Pages Specific Patterns

### Partial Page Caching

```csharp
// Cache partial view output
public class ProductCardViewComponent(IDistributedCache cache) : ViewComponent
{
    public async Task<IViewComponentResult> InvokeAsync(Guid productId)
    {
        var cacheKey = $"product-card:{productId}";
        
        var html = await cache.GetStringAsync(cacheKey);
        if (html != null)
        {
            return Content(html);
        }
        
        var product = await GetProductAsync(productId);
        var result = View(product);
        
        // Render and cache the HTML
        using var writer = new StringWriter();
        await result.RenderViewComponentAsync(writer);
        html = writer.ToString();
        
        await cache.SetStringAsync(cacheKey, html, 
            new DistributedCacheEntryOptions 
            { 
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10) 
            });
        
        return Content(html);
    }
}
```

### Cache Per User

```csharp
[OutputCache(Duration = 60, VaryByCookie = new[] { ".AspNetCore.Identity.Application" })]
public class UserDashboardModel : PageModel { }

// Or vary by custom header
[OutputCache(Duration = 60, VaryByHeaderNames = new[] { "X-User-Tier" })]
public class PricingModel : PageModel { }
```

## References

- Microsoft Docs: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/
- Output Caching: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/output
- HybridCache (.NET 9): https://learn.microsoft.com/en-us/aspnet/core/performance/caching/hybrid
- Redis Caching: https://learn.microsoft.com/en-us/aspnet/core/performance/caching/distributed
