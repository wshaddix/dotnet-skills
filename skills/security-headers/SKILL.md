---
name: security-headers
description: Security headers configuration and best practices for ASP.NET Core Razor Pages applications. Covers CSP, HSTS, X-Frame-Options, and comprehensive security middleware setup.
version: 1.0
last-updated: 2026-02-11
tags: [aspnetcore, security, headers, csp, hsts, razor-pages]
---

You are a senior .NET security architect. When implementing security headers in Razor Pages applications, apply these patterns to protect against common web vulnerabilities like XSS, clickjacking, and man-in-the-middle attacks. Target .NET 8+ with nullable reference types enabled.

## Rationale

Security headers are a critical defense-in-depth mechanism that protect applications from various attacks without changing application code. Proper configuration can prevent XSS, clickjacking, MIME sniffing, and other common vulnerabilities. These headers are supported by all modern browsers.

## Security Headers Overview

| Header | Purpose | OWASP Category |
|--------|---------|----------------|
| **Content-Security-Policy** | Prevent XSS, data injection | A7 |
| **Strict-Transport-Security** | Force HTTPS connections | A2 |
| **X-Frame-Options** | Prevent clickjacking | A6 |
| **X-Content-Type-Options** | Prevent MIME sniffing | A6 |
| **Referrer-Policy** | Control referrer information | Privacy |
| **Permissions-Policy** | Restrict browser features | Privacy |
| **X-XSS-Protection** | Legacy XSS protection | A7 |

## Pattern 1: Built-in Security Headers Middleware

ASP.NET Core provides built-in middleware for common security headers.

```csharp
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// HSTS (only in production)
if (!app.Environment.IsDevelopment())
{
    app.UseHsts(); // Adds Strict-Transport-Security header
}

// HTTPS Redirection
app.UseHttpsRedirection();

// Security headers middleware (built-in .NET 8+)
// AddHeader can be used for custom headers
```

## Pattern 2: Custom Security Headers Middleware

For comprehensive control, create custom middleware.

```csharp
public class SecurityHeadersMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context)
    {
        // Prevent MIME sniffing
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        
        // Prevent clickjacking
        context.Response.Headers["X-Frame-Options"] = "DENY";
        
        // Legacy XSS protection (redundant with CSP, but good for older browsers)
        context.Response.Headers["X-XSS-Protection"] = "1; mode=block";
        
        // Control referrer information
        context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
        
        // Permissions Policy (formerly Feature-Policy)
        context.Response.Headers["Permissions-Policy"] = 
            "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()";
        
        await next(context);
    }
}

// Extension method
public static class SecurityHeadersExtensions
{
    public static IApplicationBuilder UseSecurityHeaders(this IApplicationBuilder app)
    {
        return app.UseMiddleware<SecurityHeadersMiddleware>();
    }
}
```

### Registration

```csharp
// Program.cs
var app = builder.Build();

app.UseSecurityHeaders(); // Add early in pipeline
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
```

## Pattern 3: Content Security Policy (CSP)

CSP is the most powerful security header for preventing XSS and data injection attacks.

### Basic CSP Configuration

```csharp
public class CspMiddleware(RequestDelegate next, ILogger<CspMiddleware> logger)
{
    private const string CspHeaderName = "Content-Security-Policy";
    
    public async Task Invoke(HttpContext context)
    {
        var csp = new StringBuilder();
        
        // Default fallback
        csp.Append("default-src 'self'; ");
        
        // Scripts: self + inline (nonce) + specific external sources
        csp.Append("script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://js.stripe.com; ");
        
        // Styles: self + inline + external CDNs
        csp.Append("style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://fonts.googleapis.com; ");
        
        // Images: self + data URIs + external sources
        csp.Append("img-src 'self' data: https: blob:; ");
        
        // Fonts: self + Google Fonts
        csp.Append("font-src 'self' https://fonts.gstatic.com; ");
        
        // Connections (AJAX/WebSockets)
        csp.Append("connect-src 'self' https://api.example.com wss://ws.example.com; ");
        
        // Frames: only allow specific sources
        csp.Append("frame-src 'self' https://js.stripe.com https://hooks.stripe.com; ");
        
        // Form submissions
        csp.Append("form-action 'self'; ");
        
        // Base URI restrictions
        csp.Append("base-uri 'self'; ");
        
        // Prevent mixed content
        csp.Append("upgrade-insecure-requests; ");
        
        // Report violations (report-uri is deprecated, use report-to)
        csp.Append("report-uri /api/csp-report; ");
        
        context.Response.Headers[CspHeaderName] = csp.ToString();
        
        await next(context);
    }
}
```

### CSP with Nonce for Inline Scripts

```csharp
public class CspNonceMiddleware(RequestDelegate next)
{
    public static readonly string NonceKey = "CSP-Nonce";
    
    public async Task Invoke(HttpContext context)
    {
        // Generate cryptographically secure nonce
        var nonce = GenerateNonce();
        
        // Store in HttpContext for use in views
        context.Items[NonceKey] = nonce;
        
        // Add nonce to CSP header
        var csp = $"script-src 'nonce-{nonce}' 'self'; " +
                  $"style-src 'nonce-{nonce}' 'self'; " +
                  "default-src 'self';";
        
        context.Response.Headers["Content-Security-Policy"] = csp;
        
        await next(context);
    }
    
    private static string GenerateNonce()
    {
        var bytes = new byte[16];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(bytes);
        return Convert.ToBase64String(bytes);
    }
}

// Tag Helper for nonce
[HtmlTargetElement("script", Attributes = "asp-add-nonce")]
public class ScriptNonceTagHelper(IHttpContextAccessor httpContextAccessor) : TagHelper
{
    public override void Process(TagHelperContext context, TagHelperOutput output)
    {
        var nonce = httpContextAccessor.HttpContext?.Items[CspNonceMiddleware.NonceKey] as string;
        if (!string.IsNullOrEmpty(nonce))
        {
            output.Attributes.SetAttribute("nonce", nonce);
        }
    }
}

// Usage in Razor view
<script asp-add-nonce>
    console.log('This inline script is allowed because it has a nonce');
</script>
```

## Pattern 4: Configurable Security Headers

Allow different configurations per environment.

```csharp
public class SecurityHeadersOptions
{
    public bool UseStrictCsp { get; set; } = true;
    public List<string> AllowedScriptSources { get; set; } = new() { "'self'" };
    public List<string> AllowedStyleSources { get; set; } = new() { "'self'" };
    public List<string> AllowedImageSources { get; set; } = new() { "'self'", "data:", "https:" };
    public bool UpgradeInsecureRequests { get; set; } = true;
    public string? ReportUri { get; set; }
}

public class ConfigurableSecurityHeadersMiddleware(RequestDelegate next, IOptions<SecurityHeadersOptions> options, ILogger<ConfigurableSecurityHeadersMiddleware> logger)
{
    private readonly SecurityHeadersOptions _options = options.Value;
    
    public async Task Invoke(HttpContext context)
    {
        // Standard security headers
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.Headers["X-Frame-Options"] = "DENY";
        context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
        
        // Build CSP
        var csp = new StringBuilder();
        
        csp.Append($"default-src 'self'; ");
        csp.Append($"script-src {string.Join(" ", _options.AllowedScriptSources)}; ");
        csp.Append($"style-src {string.Join(" ", _options.AllowedStyleSources)}; ");
        csp.Append($"img-src {string.Join(" ", _options.AllowedImageSources)}; ");
        csp.Append("font-src 'self'; ");
        csp.Append("connect-src 'self'; ");
        csp.Append("form-action 'self'; ");
        csp.Append("base-uri 'self'; ");
        
        if (_options.UpgradeInsecureRequests)
        {
            csp.Append("upgrade-insecure-requests; ");
        }
        
        if (!string.IsNullOrEmpty(_options.ReportUri))
        {
            csp.Append($"report-uri {_options.ReportUri}; ");
        }
        
        context.Response.Headers["Content-Security-Policy"] = csp.ToString();
        
        await next(context);
    }
}

// Configuration in appsettings.json
{
  "SecurityHeaders": {
    "UseStrictCsp": true,
    "AllowedScriptSources": ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net"],
    "AllowedStyleSources": ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
    "UpgradeInsecureRequests": true,
    "ReportUri": "/api/csp-report"
  }
}

// Registration
builder.Services.Configure<SecurityHeadersOptions>(
    builder.Configuration.GetSection("SecurityHeaders"));
```

## Pattern 5: CSP Violation Reporting

```csharp
public class CspReportRequest
{
    [JsonPropertyName("csp-report")]
    public CspReport? Report { get; set; }
}

public class CspReport
{
    [JsonPropertyName("document-uri")]
    public string? DocumentUri { get; set; }
    
    [JsonPropertyName("referrer")]
    public string? Referrer { get; set; }
    
    [JsonPropertyName("violated-directive")]
    public string? ViolatedDirective { get; set; }
    
    [JsonPropertyName("effective-directive")]
    public string? EffectiveDirective { get; set; }
    
    [JsonPropertyName("blocked-uri")]
    public string? BlockedUri { get; set; }
    
    [JsonPropertyName("source-file")]
    public string? SourceFile { get; set; }
}

public class CspReportHandler(ILogger<CspReportHandler> logger) : IRequestHandler<CspReportRequest>
{
    public Task Handle(CspReportRequest request, CancellationToken cancellationToken)
    {
        var report = request.Report;
        
        if (report != null)
        {
            logger.LogWarning(
                "CSP Violation: {BlockedUri} blocked by {ViolatedDirective} on {DocumentUri}",
                report.BlockedUri,
                report.ViolatedDirective,
                report.DocumentUri);
        }
        
        return Task.CompletedTask;
    }
}

// Minimal API endpoint
app.MapPost("/api/csp-report", (CspReportRequest report, IMediator mediator) =>
{
    // Process asynchronously
    _ = mediator.Send(report);
    return Results.Ok();
});
```

## Pattern 6: HSTS Configuration

```csharp
// Program.cs
if (!app.Environment.IsDevelopment())
{
    // Add HSTS middleware
    app.UseHsts();
}

// Or configure explicitly
builder.Services.AddHsts(options =>
{
    options.MaxAge = TimeSpan.FromDays(365);
    options.IncludeSubDomains = true;
    options.Preload = true; // Submit to browser preload list
});

// HSTS can also be configured via web.config for IIS
```

### HSTS Preload Considerations

```csharp
// Only enable preload after thorough testing
builder.Services.AddHsts(options =>
{
    options.MaxAge = TimeSpan.FromDays(365 * 2); // Minimum 1 year for preload
    options.IncludeSubDomains = true; // Required for preload
    options.Preload = true;
});

// Before enabling preload:
// 1. Ensure HTTPS works correctly
// 2. Ensure all subdomains serve HTTPS
// 3. Test thoroughly
// 4. Submit to https://hstspreload.org/
```

## Pattern 7: Feature Policy (Permissions Policy)

Control which browser features can be used.

```csharp
public class PermissionsPolicyMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context)
    {
        // Modern Permissions-Policy header
        var permissions = new[]
        {
            "accelerometer=()",
            "camera=()",
            "geolocation=()",
            "gyroscope=()",
            "magnetometer=()",
            "microphone=()",
            "payment=()",
            "usb=()",
            "screen-wake-lock=()",
            "xr-spatial-tracking=()",
            "display-capture=()"
        };
        
        context.Response.Headers["Permissions-Policy"] = string.Join(", ", permissions);
        
        await next(context);
    }
}

// Allow specific features
// camera=(self "https://trusted-site.com")
// geolocation=(self)
```

## Pattern 8: Conditional Headers for Specific Routes

```csharp
public class ConditionalSecurityHeadersMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context)
    {
        var path = context.Request.Path.Value?.ToLowerInvariant();
        
        // Disable CSP for admin area (may use rich editors)
        if (path?.StartsWith("/admin") == true)
        {
            context.Response.Headers["Content-Security-Policy"] = "default-src 'self' 'unsafe-inline' 'unsafe-eval';";
        }
        else
        {
            // Standard CSP
            context.Response.Headers["Content-Security-Policy"] = 
                "default-src 'self'; script-src 'self'; style-src 'self';";
        }
        
        // Always add these
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.Headers["X-Frame-Options"] = "DENY";
        
        await next(context);
    }
}
```

## Pattern 9: Security Headers for Static Files

```csharp
// Custom static file options with security headers
app.UseStaticFiles(new StaticFileOptions
{
    OnPrepareResponse = ctx =>
    {
        // Add cache control for static assets
        ctx.Context.Response.Headers["Cache-Control"] = "public, max-age=31536000, immutable";
        
        // Ensure static files also get security headers
        ctx.Context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        ctx.Context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    }
});
```

## Anti-Patterns

### Overly Permissive CSP

```csharp
// ❌ BAD: Allowing everything defeats the purpose
csp.Append("default-src * 'unsafe-inline' 'unsafe-eval'; ");

// ✅ GOOD: Explicit allowlist
csp.Append("default-src 'self'; ");
csp.Append("script-src 'self' https://trusted-cdn.com; ");
```

### Missing HSTS in Production

```csharp
// ❌ BAD: No HSTS in production
if (app.Environment.IsProduction())
{
    // Missing HSTS!
}

// ✅ GOOD: HSTS always enabled in production
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}
```

### Inconsistent Header Values

```csharp
// ❌ BAD: Conflicting frame options
context.Response.Headers["X-Frame-Options"] = "DENY";
csp.Append("frame-ancestors 'self'; "); // Conflicts with DENY

// ✅ GOOD: Consistent values
context.Response.Headers["X-Frame-Options"] = "SAMEORIGIN";
csp.Append("frame-ancestors 'self'; "); // Aligns with SAMEORIGIN
```

## Testing Security Headers

```bash
# Using curl to check headers
curl -I https://your-site.com

# Using online scanners
# https://securityheaders.com/
# https://csp-evaluator.withgoogle.com/
# https://observatory.mozilla.org/
```

## References

- OWASP Secure Headers Project: https://owasp.org/www-project-secure-headers/
- CSP Quick Reference: https://content-security-policy.com/
- Mozilla MDN Security Headers: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
- Google CSP Evaluator: https://github.com/google/csp-evaluator
