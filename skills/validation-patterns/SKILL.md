---
name: validation-patterns
description: Comprehensive validation patterns for ASP.NET Core Razor Pages applications. Covers FluentValidation integration, cross-field validation, custom validators, validation behavior pipelines, and client-side validation.
version: 1.0
last-updated: 2026-02-11
tags: [aspnetcore, validation, fluentvalidation, razor-pages, data-annotations]
---

You are a senior ASP.NET Core architect specializing in input validation. When implementing validation in Razor Pages applications, apply these patterns to ensure data integrity, security, and excellent user experience. Target .NET 8+ with nullable reference types enabled.

## Rationale

Validation is critical for both security and user experience. Poor validation leads to invalid data, security vulnerabilities, and confusing error messages. These patterns provide a comprehensive approach to validation that works at multiple layers.

## Validation Strategy

| Layer | Purpose | Technology |
|-------|---------|------------|
| **Client-Side** | Immediate feedback, reduce server load | jQuery Validation, HTML5 |
| **Model Binding** | Data type/format validation | Model Binders |
| **Application** | Business rule validation | FluentValidation |
| **Database** | Constraint enforcement | EF Core Configurations |

## Pattern 1: FluentValidation Setup

### NuGet Packages

```xml
<PackageReference Include="FluentValidation" Version="11.9.*" />
<PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.9.*" />
<PackageReference Include="FluentValidation.AspNetCore" Version="11.3.*" /> <!-- For ASP.NET MVC integration -->
```

### Configuration

```csharp
// Program.cs
builder.Services.AddFluentValidationAutoValidation();
builder.Services.AddFluentValidationClientsideAdapters();

// Register all validators from assembly
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// Or register individually
builder.Services.AddScoped<IValidator<SignUpRequest>, SignUpValidator>();
```

### Basic Validator

```csharp
public class SignUpRequest
{
    public required string FirstName { get; set; }
    public required string LastName { get; set; }
    public required string Email { get; set; }
    public required string Username { get; set; }
    public required string Password { get; set; }
    public required string ConfirmPassword { get; set; }
    public required bool AcceptsTos { get; set; }
}

internal sealed class SignUpValidator : AbstractValidator<SignUpRequest>
{
    public SignUpValidator()
    {
        RuleFor(x => x.FirstName)
            .NotEmpty().WithMessage("Please enter a first name")
            .MinimumLength(3).WithMessage("First name must be at least 3 characters long")
            .MaximumLength(50).WithMessage("First name cannot exceed 50 characters")
            .Matches(@"^[a-zA-Z\s'-]+$").WithMessage("First name contains invalid characters");

        RuleFor(x => x.LastName)
            .NotEmpty().WithMessage("Please enter a last name")
            .MinimumLength(3).WithMessage("Last name must be at least 3 characters long")
            .MaximumLength(50).WithMessage("Last name cannot exceed 50 characters");

        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("Please enter an email")
            .EmailAddress().WithMessage("Please enter a valid email address")
            .MustAsync(BeUniqueEmail).WithMessage("An account with this email already exists");

        RuleFor(x => x.Username)
            .NotEmpty().WithMessage("Please enter a username")
            .MinimumLength(3).WithMessage("Username must be at least 3 characters long")
            .MaximumLength(20).WithMessage("Username cannot exceed 20 characters")
            .Matches(@"^[a-zA-Z0-9_-]+$").WithMessage("Username can only contain letters, numbers, underscores, and hyphens");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("Please enter a password")
            .MinimumLength(8).WithMessage("Password must be at least 8 characters long")
            .Matches(@"[A-Z]").WithMessage("Password must contain at least one uppercase letter")
            .Matches(@"[a-z]").WithMessage("Password must contain at least one lowercase letter")
            .Matches(@"[0-9]").WithMessage("Password must contain at least one number")
            .Matches(@"[^a-zA-Z0-9]").WithMessage("Password must contain at least one special character");

        RuleFor(x => x.ConfirmPassword)
            .Equal(x => x.Password).WithMessage("Passwords do not match");

        RuleFor(x => x.AcceptsTos)
            .Equal(true).WithMessage("You must accept our Terms of Service to sign up");
    }

    private async Task<bool> BeUniqueEmail(string email, CancellationToken cancellationToken)
    {
        // Check database for existing email
        return !await _dbContext.Users.AnyAsync(u => u.Email == email, cancellationToken);
    }
}
```

## Pattern 2: MediatR Validation Pipeline Behavior

```csharp
internal sealed class ValidationBehavior<TRequest, TResponse>(IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    private readonly IEnumerable<IValidator<TRequest>> _validators = validators ?? throw new ArgumentNullException(nameof(validators));

    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken cancellationToken)
    {
        // Skip if no validators registered
        if (!_validators.Any())
        {
            return await next(cancellationToken).ConfigureAwait(false);
        }

        var context = new ValidationContext<TRequest>(request);

        var validationResults = await Task.WhenAll(
            _validators.Select(v => v.ValidateAsync(context, cancellationToken)))
            .ConfigureAwait(false);

        var failures = validationResults
            .SelectMany(r => r.Errors)
            .Where(f => f != null)
            .ToList();

        if (failures.Count == 0)
        {
            return await next(cancellationToken).ConfigureAwait(false);
        }

        throw new ValidationException(failures);
    }
}

// Custom exception for better handling
public class ValidationException : Exception
{
    public IReadOnlyList<ValidationFailure> Errors { get; }

    public ValidationException(IEnumerable<ValidationFailure> failures)
        : base("Validation failed")
    {
        Errors = failures.ToList().AsReadOnly();
    }

    public IDictionary<string, string[]> ToDictionary()
    {
        return Errors
            .GroupBy(e => e.PropertyName)
            .ToDictionary(
                g => g.Key,
                g => g.Select(e => e.ErrorMessage).ToArray());
    }
}
```

### Registration

```csharp
builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssemblyContaining<Program>();
    cfg.AddBehavior(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
});
```

### Exception Handling Middleware

```csharp
public class ValidationExceptionHandlingMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (ValidationException ex)
        {
            await HandleValidationException(context, ex);
        }
    }

    private static async Task HandleValidationException(HttpContext context, ValidationException ex)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        context.Response.ContentType = "application/json";

        var problemDetails = new ValidationProblemDetails(ex.ToDictionary())
        {
            Type = "https://tools.ietf.org/html/rfc7231#section-6.5.1",
            Title = "Validation Failed",
            Status = StatusCodes.Status400BadRequest,
            Instance = context.Request.Path
        };

        await context.Response.WriteAsJsonAsync(problemDetails);
    }
}
```

## Pattern 3: Razor Pages Integration

### PageModel with Validation

```csharp
public class SignUpModel(IMediator mediator) : PageModel
{
    [BindProperty]
    public required SignUpFormData FormData { get; set; }

    public IActionResult OnGet()
    {
        return Page();
    }

    public async Task<IActionResult> OnPostAsync()
    {
        if (!ModelState.IsValid)
        {
            return Page();
        }

        try
        {
            var response = await mediator.Send(new SignUpRequest
            {
                Email = FormData.Email,
                Password = FormData.Password,
                // ... map other properties
            });

            return RedirectToPage("/Success");
        }
        catch (ValidationException ex)
        {
            // Add validation errors to ModelState
            foreach (var error in ex.Errors)
            {
                ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
            }
            
            return Page();
        }
    }
}

public sealed class SignUpFormData
{
    [Required(ErrorMessage = "Please enter a first name")]
    [MinLength(3, ErrorMessage = "First name must be at least 3 characters long")]
    public required string FirstName { get; set; }

    [Required(ErrorMessage = "Please enter an email")]
    [EmailAddress(ErrorMessage = "Please enter a valid email address")]
    public required string Email { get; set; }

    [Required(ErrorMessage = "Please enter a password")]
    [MinLength(8, ErrorMessage = "Password must be at least 8 characters long")]
    public required string Password { get; set; }

    [Compare(nameof(Password), ErrorMessage = "Passwords do not match")]
    public required string ConfirmPassword { get; set; }
}
```

### View with Validation Display

```csharp
@page
@model SignUpModel
@{
    ViewData["Title"] = "Sign Up";
}

<form method="post">
    <div asp-validation-summary="ModelOnly" class="text-danger"></div>
    
    <div class="form-group">
        <label asp-for="FormData.FirstName"></label>
        <input asp-for="FormData.FirstName" class="form-control" />
        <span asp-validation-for="FormData.FirstName" class="text-danger"></span>
    </div>
    
    <div class="form-group">
        <label asp-for="FormData.Email"></label>
        <input asp-for="FormData.Email" class="form-control" type="email" />
        <span asp-validation-for="FormData.Email" class="text-danger"></span>
    </div>
    
    <div class="form-group">
        <label asp-for="FormData.Password"></label>
        <input asp-for="FormData.Password" class="form-control" type="password" />
        <span asp-validation-for="FormData.Password" class="text-danger"></span>
    </div>
    
    <div class="form-group">
        <label asp-for="FormData.ConfirmPassword"></label>
        <input asp-for="FormData.ConfirmPassword" class="form-control" type="password" />
        <span asp-validation-for="FormData.ConfirmPassword" class="text-danger"></span>
    </div>
    
    <button type="submit" class="btn btn-primary">Sign Up</button>
</form>

@section Scripts {
    <partial name="_ValidationScriptsPartial" />
}
```

## Pattern 4: Advanced FluentValidation Patterns

### Conditional Validation

```csharp
public class OrderValidator : AbstractValidator<OrderRequest>
{
    public OrderValidator()
    {
        RuleFor(x => x.ShippingAddress)
            .NotEmpty()
            .When(x => x.RequiresShipping)
            .WithMessage("Shipping address is required when shipping is needed");

        RuleFor(x => x.PickupLocation)
            .NotEmpty()
            .When(x => !x.RequiresShipping)
            .WithMessage("Pickup location is required for in-store pickup");

        // Cross-field conditional validation
        When(x => x.IsExpressShipping, () =>
        {
            RuleFor(x => x.ShippingAddress.Country)
                .Must(BeSupportedCountry)
                .WithMessage("Express shipping is not available for this country");
        });
    }

    private bool BeSupportedCountry(string? country)
    {
        var supportedCountries = new[] { "US", "CA", "UK", "DE", "FR" };
        return country != null && supportedCountries.Contains(country);
    }
}
```

### Collection Validation

```csharp
public class OrderRequest
{
    public required List<OrderItem> Items { get; set; }
}

public class OrderRequestValidator : AbstractValidator<OrderRequest>
{
    public OrderRequestValidator()
    {
        RuleFor(x => x.Items)
            .NotEmpty().WithMessage("Order must contain at least one item")
            .Must(items => items.Count <= 100).WithMessage("Order cannot contain more than 100 items");

        RuleForEach(x => x.Items).ChildRules(item =>
        {
            item.RuleFor(x => x.ProductId)
                .NotEmpty().WithMessage("Product is required");

            item.RuleFor(x => x.Quantity)
                .GreaterThan(0).WithMessage("Quantity must be greater than 0")
                .LessThanOrEqualTo(999).WithMessage("Quantity cannot exceed 999");
        });
    }
}
```

### Async Database Validation

```csharp
public class CreateProductValidator : AbstractValidator<CreateProductRequest>
{
    private readonly AppDbContext _dbContext;

    public CreateProductValidator(AppDbContext dbContext)
    {
        _dbContext = dbContext;

        RuleFor(x => x.Sku)
            .NotEmpty()
            .MustAsync(BeUniqueSku).WithMessage("SKU already exists");

        RuleFor(x => x.CategoryId)
            .MustAsync(BeValidCategory).WithMessage("Invalid category");
    }

    private async Task<bool> BeUniqueSku(string sku, CancellationToken cancellationToken)
    {
        return !await _dbContext.Products
            .AnyAsync(p => p.Sku == sku, cancellationToken);
    }

    private async Task<bool> BeValidCategory(Guid categoryId, CancellationToken cancellationToken)
    {
        return await _dbContext.Categories
            .AnyAsync(c => c.Id == categoryId, cancellationToken);
    }
}
```

### Custom Validators

```csharp
// Reusable custom validator
public static class CustomValidators
{
    public static IRuleBuilderOptions<T, string> MustBeStrongPassword<T>(
        this IRuleBuilder<T, string> ruleBuilder)
    {
        return ruleBuilder
            .MinimumLength(12)
            .Matches(@"[A-Z]").WithMessage("Password must contain at least one uppercase letter")
            .Matches(@"[a-z]").WithMessage("Password must contain at least one lowercase letter")
            .Matches(@"[0-9]").WithMessage("Password must contain at least one number")
            .Matches(@"[^a-zA-Z0-9]").WithMessage("Password must contain at least one special character")
            .Must(NotContainCommonPasswords).WithMessage("Password is too common");
    }

    private static bool NotContainCommonPasswords(string password)
    {
        var commonPasswords = new[] { "password", "123456", "qwerty" };
        return !commonPasswords.Any(common => 
            password.Contains(common, StringComparison.OrdinalIgnoreCase));
    }
}

// Usage
public class UserValidator : AbstractValidator<CreateUserRequest>
{
    public UserValidator()
    {
        RuleFor(x => x.Password)
            .NotEmpty()
            .MustBeStrongPassword();
    }
}
```

## Pattern 5: Custom Data Annotations

```csharp
[AttributeUsage(AttributeTargets.Property)]
public class MustBeTrueAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value is bool boolValue && boolValue)
        {
            return ValidationResult.Success;
        }

        return new ValidationResult(ErrorMessage ?? "This field must be true");
    }
}

// Usage in Razor Page model
public class TermsAcceptanceModel
{
    [MustBeTrue(ErrorMessage = "You must accept the terms and conditions")]
    public required bool AcceptTerms { get; set; }
}

[AttributeUsage(AttributeTargets.Property)]
public class MinimumAgeAttribute : ValidationAttribute
{
    private readonly int _minimumAge;

    public MinimumAgeAttribute(int minimumAge)
    {
        _minimumAge = minimumAge;
    }

    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value is DateTime dateOfBirth)
        {
            var age = DateTime.Today.Year - dateOfBirth.Year;
            if (dateOfBirth.Date > DateTime.Today.AddYears(-age)) age--;

            if (age >= _minimumAge)
            {
                return ValidationResult.Success;
            }
        }

        return new ValidationResult($"You must be at least {_minimumAge} years old");
    }
}
```

## Pattern 6: String Trimming Model Binder

```csharp
// Prevents whitespace-only inputs and trims strings automatically
public class StringTrimModelBinder(IModelBinder fallbackBinder) : IModelBinder
{
    private readonly IModelBinder _fallbackBinder = fallbackBinder ?? throw new ArgumentNullException(nameof(fallbackBinder));

    public async Task BindModelAsync(ModelBindingContext bindingContext)
    {
        ArgumentNullException.ThrowIfNull(bindingContext);

        var modelType = bindingContext.ModelType;
        if (modelType != typeof(string) && (Nullable.GetUnderlyingType(modelType) != typeof(string)))
        {
            await _fallbackBinder.BindModelAsync(bindingContext).ConfigureAwait(false);
            return;
        }

        var valueProviderResult = bindingContext.ValueProvider.GetValue(bindingContext.ModelName);
        if (valueProviderResult == ValueProviderResult.None)
        {
            return;
        }

        bindingContext.ModelState.SetModelValue(bindingContext.ModelName, valueProviderResult);

        var value = valueProviderResult.FirstValue;
        var trimmedValue = value?.Trim();

        // Treat whitespace-only as null/empty
        if (string.IsNullOrWhiteSpace(trimmedValue))
        {
            trimmedValue = null;
        }

        bindingContext.Result = ModelBindingResult.Success(trimmedValue);
    }
}

// Provider to register the binder
public class StringTrimModelBinderProvider : IModelBinderProvider
{
    public IModelBinder? GetBinder(ModelBinderProviderContext context)
    {
        if (context.Metadata.ModelType == typeof(string))
        {
            return new StringTrimModelBinder(
                context.Services.GetRequiredService<SimpleTypeModelBinder>());
        }

        return null;
    }
}

// Registration
builder.Services.AddRazorPages().AddMvcOptions(options =>
{
    options.ModelBinderProviders.Insert(0, new StringTrimModelBinderProvider());
});
```

## Pattern 7: Validation Helper Methods in PageModelBase

```csharp
public abstract class PageModelBase : PageModel
{
    protected void AddValidationError(string propertyName, string message)
    {
        ModelState.AddModelError(propertyName, message);
    }

    protected void AddValidationError(string message)
    {
        ModelState.AddModelError(string.Empty, message);
    }

    protected bool HasValidationErrors => !ModelState.IsValid;

    protected IActionResult ReturnWithValidationErrors()
    {
        return Page();
    }

    protected async Task<IActionResult> SafePostAsync(
        Func<Task<IActionResult>> action, 
        Action? onValidationError = null)
    {
        if (!ModelState.IsValid)
        {
            onValidationError?.Invoke();
            return Page();
        }

        try
        {
            return await action();
        }
        catch (ValidationException ex)
        {
            foreach (var error in ex.Errors)
            {
                ModelState.AddModelError(
                    error.PropertyName, 
                    error.ErrorMessage);
            }
            return Page();
        }
    }
}
```

## Pattern 8: Validating File Uploads

```csharp
public class FileUploadRequest
{
    public required IFormFile File { get; set; }
    public string? Description { get; set; }
}

public class FileUploadValidator : AbstractValidator<FileUploadRequest>
{
    private readonly string[] _allowedExtensions = new[] { ".jpg", ".jpeg", ".png", ".pdf" };
    private const long MaxFileSize = 10 * 1024 * 1024; // 10MB

    public FileUploadValidator()
    {
        RuleFor(x => x.File)
            .NotNull()
            .Must(BeValidSize).WithMessage("File size must not exceed 10MB")
            .Must(BeValidExtension).WithMessage("Invalid file type. Allowed: .jpg, .jpeg, .png, .pdf");

        RuleFor(x => x.Description)
            .MaximumLength(500).When(x => !string.IsNullOrEmpty(x.Description));
    }

    private bool BeValidSize(IFormFile file)
    {
        return file.Length <= MaxFileSize;
    }

    private bool BeValidExtension(IFormFile file)
    {
        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        return _allowedExtensions.Contains(extension);
    }
}
```

## Anti-Patterns

### Duplicate Validation

```csharp
// ❌ BAD: Validation in multiple places
// PageModel
if (string.IsNullOrEmpty(model.Email))
    ModelState.AddModelError("Email", "Required");

// Validator
RuleFor(x => x.Email).NotEmpty(); // Duplicate!

// ✅ GOOD: Centralize validation in validators
// PageModel just checks ModelState.IsValid
```

### Silent Validation Failures

```csharp
// ❌ BAD: Ignoring validation results
catch (ValidationException ex)
{
    // Silently ignoring!
    return Page();
}

// ✅ GOOD: Always add errors to ModelState
catch (ValidationException ex)
{
    foreach (var error in ex.Errors)
    {
        ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
    }
    return Page();
}
```

### Trusting Client-Side Validation

```csharp
// ❌ BAD: Only client-side validation
// Always validate server-side
public IActionResult OnPost(UserInput input)
{
    // Missing server-side validation!
    SaveToDatabase(input);
}

// ✅ GOOD: Server-side always validates
public IActionResult OnPost(UserInput input)
{
    if (!ModelState.IsValid) // Always check
        return Page();
    
    SaveToDatabase(input);
}
```

## References

- FluentValidation: https://docs.fluentvalidation.net/
- ASP.NET Core Validation: https://learn.microsoft.com/en-us/aspnet/core/mvc/models/validation
- Data Annotations: https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.dataannotations
- jQuery Validation: https://jqueryvalidation.org/
