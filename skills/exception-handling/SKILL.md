---
name: exception-handling
description: Comprehensive exception handling patterns for ASP.NET Core Razor Pages applications. Covers global exception handling, ProblemDetails API, custom error pages, exception middleware, and graceful degradation strategies. Use when implementing error handling in Razor Pages applications, configuring global exception middleware, or creating user-friendly error pages and API error responses.
---

You are a senior ASP.NET Core architect specializing in exception handling. When implementing error handling in Razor Pages applications, apply these patterns to ensure graceful failures, proper logging, and excellent user experience. Target .NET 8+ with nullable reference types enabled.

## Rationale

Proper exception handling is critical for production applications. Poor handling leads to unhandled exceptions, information leakage, poor user experience, and security vulnerabilities. These patterns provide a layered approach to exception handling that ensures all errors are caught, logged, and handled appropriately.

## Exception Handling Layers

| Layer | Purpose | Scope |
|-------|---------|-------|
| **Global Middleware** | Catch-all unhandled exceptions | Application-wide |
| **Exception Filter** | Handle controller/page-specific exceptions | PageModel |
| **Try-Catch Blocks** | Handle specific operations | Method level |
| **Error Pages** | Display user-friendly errors | UI |

## Pattern 1: Global Exception Handler Configuration

### Program.cs Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

// Configure exception handling middleware (order matters!)
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage(); // Detailed errors for dev
}
else
{
    app.UseExceptionHandler("/Error"); // Production error page
    app.UseStatusCodePagesWithReExecute("/NotFound", "?statusCode={0}");
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();

app.MapRazorPages();
```

### Error Page Model

```csharp
[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
[IgnoreAntiforgeryToken]
public class ErrorModel(ILogger<ErrorModel> logger, IWebHostEnvironment env) : PageModel
{
    public string? RequestId { get; set; }
    public bool ShowRequestId => !string.IsNullOrEmpty(RequestId);
    public string? ErrorMessage { get; set; }
    public string? StackTrace { get; set; }
    public int StatusCode { get; set; } = 500;

    public void OnGet(int? statusCode = null)
    {
        RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier;
        StatusCode = statusCode ?? 500;

        var exceptionHandlerPathFeature = HttpContext.Features.Get<IExceptionHandlerPathFeature>();
        
        if (exceptionHandlerPathFeature?.Error != null)
        {
            var ex = exceptionHandlerPathFeature.Error;
            var path = exceptionHandlerPathFeature.Path;
            
            logger.LogError(ex, 
                "Unhandled exception at {Path}. RequestId: {RequestId}", 
                path, RequestId);

            // Only expose details in development
            if (env.IsDevelopment())
            {
                ErrorMessage = ex.Message;
                StackTrace = ex.StackTrace;
            }
            else
            {
                ErrorMessage = "An unexpected error occurred. Please try again later.";
            }
        }
    }
}
```

### Error.cshtml

```csharp
@page
@model ErrorModel
@{
    ViewData["Title"] = "Error";
}

<h1 class="text-danger">Error</h1>
<h2 class="text-danger">An error occurred while processing your request.</h2>

@if (Model.ShowRequestId)
{
    <p>
        <strong>Request ID:</strong> <code>@Model.RequestId</code>
    </p>
    <p class="text-muted">
        Please include this ID when contacting support.
    </p>
}

@if (!string.IsNullOrEmpty(Model.ErrorMessage))
{
    <h3>Error Details</h3>
    <p>@Model.ErrorMessage</p>
    
    @if (!string.IsNullOrEmpty(Model.StackTrace))
    {
        <pre class="alert alert-secondary">@Model.StackTrace</pre>
    }
}
```

## Pattern 2: Status Code Pages

### NotFound Page Model

```csharp
[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
public class NotFoundModel : PageModel
{
    public int StatusCode { get; set; }
    public string? OriginalPath { get; set; }

    public void OnGet(int statusCode)
    {
        StatusCode = statusCode;
        OriginalPath = HttpContext.Features.Get<IStatusCodeReExecuteFeature>()?.OriginalPath;
    }
}
```

### NotFound.cshtml

```csharp
@page
@model NotFoundModel
@{
    ViewData["Title"] = "Not Found";
}

<div class="text-center">
    <h1 class="display-1">@Model.StatusCode</h1>
    <h2>Page Not Found</h2>
    
    @if (!string.IsNullOrEmpty(Model.OriginalPath))
    {
        <p>The page <code>@Model.OriginalPath</code> could not be found.</p>
    }
    
    <a asp-page="/Index" class="btn btn-primary">Return to Home</a>
</div>
```

## Pattern 3: Custom Exception Middleware

For more control than the built-in exception handler, create custom middleware.

```csharp
public class GlobalExceptionHandlingMiddleware(RequestDelegate next, ILogger<GlobalExceptionHandlingMiddleware> logger)
{
    public async Task Invoke(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        logger.LogError(exception, "Unhandled exception occurred");

        context.Response.ContentType = "application/json";
        
        var response = exception switch
        {
            ValidationException ex => CreateValidationErrorResponse(context, ex),
            NotFoundException ex => CreateNotFoundResponse(context, ex),
            UnauthorizedAccessException ex => CreateUnauthorizedResponse(context, ex),
            ConflictException ex => CreateConflictResponse(context, ex),
            _ => CreateGenericErrorResponse(context, exception)
        };

        context.Response.StatusCode = response.Status ?? 500;
        await context.Response.WriteAsJsonAsync(response);
    }

    private static ProblemDetails CreateValidationErrorResponse(HttpContext context, ValidationException ex)
    {
        return new ValidationProblemDetails(ex.Errors)
        {
            Status = StatusCodes.Status400BadRequest,
            Type = "https://tools.ietf.org/html/rfc7231#section-6.5.1",
            Title = "Validation Failed",
            Detail = "One or more validation errors occurred",
            Instance = context.Request.Path
        };
    }

    private static ProblemDetails CreateNotFoundResponse(HttpContext context, NotFoundException ex)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status404NotFound,
            Type = "https://tools.ietf.org/html/rfc7231#section-6.5.4",
            Title = "Not Found",
            Detail = ex.Message,
            Instance = context.Request.Path
        };
    }

    private static ProblemDetails CreateUnauthorizedResponse(HttpContext context, UnauthorizedAccessException ex)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status403Forbidden,
            Type = "https://tools.ietf.org/html/rfc7231#section-6.5.3",
            Title = "Forbidden",
            Detail = "You do not have permission to perform this action",
            Instance = context.Request.Path
        };
    }

    private static ProblemDetails CreateConflictResponse(HttpContext context, ConflictException ex)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status409Conflict,
            Type = "https://tools.ietf.org/html/rfc7231#section-6.5.8",
            Title = "Conflict",
            Detail = ex.Message,
            Instance = context.Request.Path
        };
    }

    private static ProblemDetails CreateGenericErrorResponse(HttpContext context, Exception ex)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Type = "https://tools.ietf.org/html/rfc7231#section-6.6.1",
            Title = "Internal Server Error",
            Detail = "An unexpected error occurred",
            Instance = context.Request.Path
        };
    }
}

// Extension method
public static class ExceptionHandlingExtensions
{
    public static IApplicationBuilder UseGlobalExceptionHandling(this IApplicationBuilder app)
    {
        return app.UseMiddleware<GlobalExceptionHandlingMiddleware>();
    }
}
```

## Pattern 4: Custom Exceptions

Define domain-specific exceptions for different error scenarios.

```csharp
// Base exception
public abstract class DomainException : Exception
{
    protected DomainException(string message) : base(message) { }
    protected DomainException(string message, Exception inner) : base(message, inner) { }
}

// Not Found
public class NotFoundException : DomainException
{
    public NotFoundException(string entityType, object id)
        : base($"{entityType} with id '{id}' was not found.") { }

    public NotFoundException(string message) : base(message) { }
}

// Validation
public class ValidationException : DomainException
{
    public IReadOnlyDictionary<string, string[]> Errors { get; }

    public ValidationException(IDictionary<string, string[]> errors)
        : base("Validation failed")
    {
        Errors = new ReadOnlyDictionary<string, string[]>(errors);
    }

    public ValidationException(string propertyName, string errorMessage)
        : base("Validation failed")
    {
        Errors = new ReadOnlyDictionary<string, string[]>(
            new Dictionary<string, string[]> { [propertyName] = new[] { errorMessage } });
    }
}

// Conflict
public class ConflictException : DomainException
{
    public ConflictException(string message) : base(message) { }
}

// Business Rule Violation
public class BusinessRuleException : DomainException
{
    public string RuleCode { get; }

    public BusinessRuleException(string ruleCode, string message)
        : base(message)
    {
        RuleCode = ruleCode;
    }
}
```

## Pattern 5: ProblemDetails API

ASP.NET Core 7+ includes built-in ProblemDetails support.

```csharp
// Program.cs
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = ctx =>
    {
        ctx.ProblemDetails.Instance = ctx.HttpContext.Request.Path;
        ctx.ProblemDetails.Extensions["traceId"] = Activity.Current?.Id ?? ctx.HttpContext.TraceIdentifier;
        ctx.ProblemDetails.Extensions["timestamp"] = DateTimeOffset.UtcNow;
        
        if (ctx.HttpContext.User.Identity?.IsAuthenticated == true)
        {
            ctx.ProblemDetails.Extensions["userId"] = ctx.HttpContext.User.Identity.Name;
        }
    };
});

var app = builder.Build();
app.UseExceptionHandler();
app.UseStatusCodePages();
```

### Custom ProblemDetails Factory

```csharp
public class CustomProblemDetailsFactory : ProblemDetailsFactory
{
    public override ProblemDetails CreateProblemDetails(
        HttpContext httpContext,
        int? statusCode = null,
        string? title = null,
        string? type = null,
        string? detail = null,
        string? instance = null)
    {
        var problemDetails = new ProblemDetails
        {
            Status = statusCode ?? 500,
            Title = title,
            Type = type,
            Detail = detail,
            Instance = instance ?? httpContext.Request.Path
        };

        // Add correlation ID
        if (httpContext.Request.Headers.TryGetValue("X-Correlation-Id", out var correlationId))
        {
            problemDetails.Extensions["correlationId"] = correlationId.ToString();
        }

        return problemDetails;
    }

    public override ValidationProblemDetails CreateValidationProblemDetails(
        HttpContext httpContext,
        ModelStateDictionary modelStateDictionary,
        int? statusCode = null,
        string? title = null,
        string? type = null,
        string? detail = null,
        string? instance = null)
    {
        var validationProblemDetails = new ValidationProblemDetails(modelStateDictionary)
        {
            Status = statusCode ?? 400,
            Title = title ?? "Validation Failed",
            Type = type,
            Detail = detail,
            Instance = instance ?? httpContext.Request.Path
        };

        return validationProblemDetails;
    }
}

// Register
builder.Services.AddSingleton<ProblemDetailsFactory, CustomProblemDetailsFactory>();
```

## Pattern 6: Handler-Level Exception Handling

```csharp
public abstract class SafePageModel : PageModel
{
    protected async Task<IActionResult> TryAsync(Func<Task<IActionResult>> action)
    {
        try
        {
            return await action();
        }
        catch (NotFoundException ex)
        {
            TempData["ErrorMessage"] = ex.Message;
            return NotFound();
        }
        catch (ValidationException ex)
        {
            foreach (var error in ex.Errors)
            {
                ModelState.AddModelError(error.Key, string.Join(", ", error.Value));
            }
            return Page();
        }
        catch (ConflictException ex)
        {
            ModelState.AddModelError(string.Empty, ex.Message);
            return Page();
        }
        catch (Exception ex)
        {
            // Log and return generic error
            TempData["ErrorMessage"] = "An unexpected error occurred. Please try again.";
            return RedirectToPage("/Error");
        }
    }
}

// Usage
public class OrderDetailsModel(IOrderService orderService) : SafePageModel
{
    public Order? Order { get; set; }

    public Task<IActionResult> OnGetAsync(Guid id)
    {
        return TryAsync(async () =>
        {
            Order = await orderService.GetAsync(id);
            return Page();
        });
    }
}
```

## Pattern 7: Background Service Exception Handling

```csharp
public class EmailOutboxProcessor(ILogger<EmailOutboxProcessor> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ProcessOutboxAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                // Expected during shutdown
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing email outbox");
                // Wait before retrying
                await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
            }
        }
    }

    private async Task ProcessOutboxAsync(CancellationToken ct)
    {
        // Processing logic here
    }
}
```

## Pattern 8: MediatR Exception Handling Behavior

```csharp
public class ExceptionHandlingBehavior<TRequest, TResponse>(ILogger<ExceptionHandlingBehavior<TRequest, TResponse>> logger)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        try
        {
            return await next(cancellationToken);
        }
        catch (DomainException)
        {
            // Domain exceptions are expected - rethrow for handling upstream
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, 
                "Unexpected error handling {RequestName}", 
                typeof(TRequest).Name);
            
            throw new ApplicationException(
                $"Error processing request {typeof(TRequest).Name}", ex);
        }
    }
}
```

## Anti-Patterns

### Swallowing Exceptions

```csharp
// ❌ BAD: Silent failure
try
{
    await _service.DoWorkAsync();
}
catch (Exception)
{
    // Nothing logged, nothing thrown!
}

// ✅ GOOD: Log and either handle or rethrow
catch (Exception ex)
{
    _logger.LogError(ex, "Failed to complete work");
    throw; // Or handle gracefully
}
```

### Catching Generic Exception Too Early

```csharp
// ❌ BAD: Catching generic exception too early prevents proper handling
try
{
    var user = await _userService.GetAsync(id);
    var order = await _orderService.CreateAsync(user, request);
}
catch (Exception ex) // Catches everything
{
    // Can't distinguish between user not found and order creation failure
}

// ✅ GOOD: Catch specific exceptions where they occur
try
{
    var user = await _userService.GetAsync(id);
}
catch (NotFoundException ex)
{
    return NotFound(ex.Message);
}

try
{
    var order = await _orderService.CreateAsync(user, request);
}
catch (ValidationException ex)
{
    return BadRequest(ex.Errors);
}
```

### Leaking Sensitive Information

```csharp
// ❌ BAD: Exposing internal details in production
catch (Exception ex)
{
    return Content($"Database connection failed: {ex.StackTrace}");
}

// ✅ GOOD: Generic message in production, details in development
catch (Exception ex)
{
    _logger.LogError(ex, "Internal error");
    
    if (_env.IsDevelopment())
    {
        return Content(ex.ToString());
    }
    
    return Content("An error occurred");
}
```

## References

- Exception Handling: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling
- ProblemDetails: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/handle-errors
- Status Code Pages: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling#usestatuscodepages
