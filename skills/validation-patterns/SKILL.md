---
name: validation-patterns
description: Comprehensive validation patterns for ASP.NET Core applications. Covers FluentValidation integration, DataAnnotations, IValidatableObject, IValidateOptions<T>, MediatR pipeline behavior, and client-side validation. Use when implementing validation in ASP.NET Core applications, setting up FluentValidation, creating custom validators, configuring options validation, or implementing cross-field validation.
---

# Validation Patterns in ASP.NET Core

## Rationale

Validation is critical for both security and user experience. Poor validation leads to invalid data, security vulnerabilities, and confusing error messages. These patterns provide a comprehensive approach to validation at multiple layers.

## Validation Strategy

| Layer | Purpose | Technology |
|-------|---------|------------|
| **Client-Side** | Immediate feedback, reduce server load | jQuery Validation, HTML5 |
| **Model Binding** | Data type/format validation | Model Binders |
| **Application** | Business rule validation | FluentValidation, DataAnnotations |
| **Configuration** | Startup validation | IValidateOptions<T> |
| **Database** | Constraint enforcement | EF Core Configurations |

## Validation Approach Decision Tree

Choose the validation approach based on complexity:

1. **DataAnnotations** (default) -- declarative `[Required]`, `[Range]`, `[StringLength]`, `[RegularExpression]` attributes. Best for simple property-level constraints.
2. **`IValidatableObject`** -- implement `Validate()` for cross-property rules. Best for date range comparisons, conditional required fields.
3. **Custom `ValidationAttribute`** -- subclass `ValidationAttribute` for reusable property-level rules.
4. **`IValidateOptions<T>`** -- validate configuration/options classes at startup with access to DI services.
5. **FluentValidation** -- third-party library for complex, testable validation with fluent API. Best for async validators, database-dependent rules.

---

## Pattern 1: DataAnnotations

The `System.ComponentModel.DataAnnotations` namespace provides declarative validation through attributes.

```csharp
using System.ComponentModel.DataAnnotations;

public sealed class CreateProductRequest
{
    [Required(ErrorMessage = "Product name is required")]
    [StringLength(200, MinimumLength = 1)]
    public required string Name { get; set; }

    [Range(0.01, 1_000_000, ErrorMessage = "Price must be between {1} and {2}")]
    public decimal Price { get; set; }

    [RegularExpression(@"^[A-Z]{2,4}-\d{4,8}$",
        ErrorMessage = "SKU format: AA-0000 to AAAA-00000000")]
    public string? Sku { get; set; }

    [EmailAddress]
    public string? ContactEmail { get; set; }

    [Url]
    public string? WebsiteUrl { get; set; }

    [Range(0, int.MaxValue, ErrorMessage = "Quantity cannot be negative")]
    public int Quantity { get; set; }
}
```

### Attribute Reference

| Attribute | Purpose | Example |
|-----------|---------|---------|
| `[Required]` | Non-null, non-empty | `[Required]` |
| `[StringLength]` | Min/max length | `[StringLength(200, MinimumLength = 1)]` |
| `[Range]` | Numeric/date range | `[Range(1, 100)]` |
| `[RegularExpression]` | Pattern match | `[RegularExpression(@"^\d{5}$")]` |
| `[EmailAddress]` | Email format | `[EmailAddress]` |
| `[Phone]` | Phone format | `[Phone]` |
| `[Url]` | URL format | `[Url]` |
| `[CreditCard]` | Luhn check | `[CreditCard]` |
| `[Compare]` | Property equality | `[Compare(nameof(Password))]` |
| `[MaxLength]` / `[MinLength]` | Collection/string length | `[MaxLength(50)]` |
| `[AllowedValues]` (.NET 8+) | Value allowlist | `[AllowedValues("Draft", "Published")]` |
| `[DeniedValues]` (.NET 8+) | Value denylist | `[DeniedValues("Admin", "Root")]` |
| `[Length]` (.NET 8+) | Min and max in one | `[Length(1, 200)]` |
| `[Base64String]` (.NET 8+) | Base64 format | `[Base64String]` |

---

## Pattern 2: Custom ValidationAttribute

Create reusable validation attributes for domain-specific rules.

### Property-Level

```csharp
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Parameter)]
public sealed class FutureDateAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(
        object? value, ValidationContext validationContext)
    {
        if (value is DateOnly date && date <= DateOnly.FromDateTime(DateTime.UtcNow))
        {
            return new ValidationResult(
                ErrorMessage ?? "Date must be in the future",
                [validationContext.MemberName!]);
        }

        return ValidationResult.Success;
    }
}

public sealed class CreateEventRequest
{
    [Required]
    [StringLength(200)]
    public required string Title { get; set; }

    [FutureDate(ErrorMessage = "Event date must be in the future")]
    public DateOnly EventDate { get; set; }
}
```

### Class-Level

```csharp
[AttributeUsage(AttributeTargets.Class)]
public sealed class DateRangeAttribute : ValidationAttribute
{
    public string StartProperty { get; set; } = "StartDate";
    public string EndProperty { get; set; } = "EndDate";

    protected override ValidationResult? IsValid(
        object? value, ValidationContext validationContext)
    {
        if (value is null) return ValidationResult.Success;

        var type = value.GetType();
        var startValue = type.GetProperty(StartProperty)?.GetValue(value);
        var endValue = type.GetProperty(EndProperty)?.GetValue(value);

        if (startValue is DateOnly start && endValue is DateOnly end && end < start)
        {
            return new ValidationResult(
                ErrorMessage ?? $"{EndProperty} must be after {StartProperty}",
                [EndProperty]);
        }

        return ValidationResult.Success;
    }
}
```

---

## Pattern 3: IValidatableObject

Implement `IValidatableObject` for cross-property validation within the model:

```csharp
public sealed class CreateOrderRequest : IValidatableObject
{
    [Required]
    [StringLength(50)]
    public required string CustomerId { get; set; }

    [Required]
    public DateOnly OrderDate { get; set; }

    public DateOnly? ShipByDate { get; set; }

    [Required]
    [MinLength(1, ErrorMessage = "At least one line item is required")]
    public required List<OrderLineItem> Lines { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (ShipByDate.HasValue && ShipByDate.Value <= OrderDate)
        {
            yield return new ValidationResult(
                "Ship-by date must be after order date",
                [nameof(ShipByDate)]);
        }

        if (Lines.Sum(l => l.Quantity * l.UnitPrice) > 1_000_000)
        {
            yield return new ValidationResult(
                "Total order value cannot exceed 1,000,000",
                [nameof(Lines)]);
        }

        if (Lines.Any(l => l.RequiresShipping) && ShipByDate is null)
        {
            yield return new ValidationResult(
                "Ship-by date is required when order contains shippable items",
                [nameof(ShipByDate)]);
        }
    }
}
```

**When to use `IValidatableObject` vs custom attribute:** Use `IValidatableObject` when validation logic is specific to one model. Use custom `ValidationAttribute` when the same rule applies across multiple models.

---

## Pattern 4: IValidateOptions<T>

Validate configuration/options classes at startup with access to DI services:

```csharp
public sealed class DatabaseOptions
{
    public const string SectionName = "Database";

    public string ConnectionString { get; set; } = "";
    public int MaxRetryCount { get; set; } = 3;
    public int CommandTimeoutSeconds { get; set; } = 30;
    public int MaxPoolSize { get; set; } = 100;
    public int MinPoolSize { get; set; } = 0;
}

public sealed class DatabaseOptionsValidator : IValidateOptions<DatabaseOptions>
{
    public ValidateOptionsResult Validate(string? name, DatabaseOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            failures.Add("Database connection string is required.");
        }

        if (options.MaxRetryCount is < 0 or > 10)
        {
            failures.Add("MaxRetryCount must be between 0 and 10.");
        }

        if (options.MinPoolSize > options.MaxPoolSize)
        {
            failures.Add($"MinPoolSize ({options.MinPoolSize}) cannot exceed MaxPoolSize ({options.MaxPoolSize}).");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}
```

### Registration

```csharp
builder.Services
    .AddOptions<DatabaseOptions>()
    .BindConfiguration(DatabaseOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddSingleton<IValidateOptions<DatabaseOptions>, DatabaseOptionsValidator>();
```

---

## Pattern 5: FluentValidation Setup

### NuGet Packages

```xml
<PackageReference Include="FluentValidation" Version="11.9.*" />
<PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.9.*" />
```

### Configuration

```csharp
builder.Services.AddFluentValidationAutoValidation();
builder.Services.AddFluentValidationClientsideAdapters();
builder.Services.AddValidatorsFromAssemblyContaining<Program>();
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

        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("Please enter an email")
            .EmailAddress().WithMessage("Please enter a valid email address")
            .MustAsync(BeUniqueEmail).WithMessage("An account with this email already exists");

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
        return !await _dbContext.Users.AnyAsync(u => u.Email == email, cancellationToken);
    }
}
```

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

        When(x => x.IsExpressShipping, () =>
        {
            RuleFor(x => x.ShippingAddress.Country)
                .Must(BeSupportedCountry)
                .WithMessage("Express shipping is not available for this country");
        });
    }
}
```

### Collection Validation

```csharp
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

---

## Pattern 6: MediatR Validation Pipeline Behavior

```csharp
internal sealed class ValidationBehavior<TRequest, TResponse>(IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken cancellationToken)
    {
        if (!validators.Any())
        {
            return await next(cancellationToken).ConfigureAwait(false);
        }

        var context = new ValidationContext<TRequest>(request);

        var validationResults = await Task.WhenAll(
            validators.Select(v => v.ValidateAsync(context, cancellationToken)))
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

---

## Pattern 7: Manual Validation

Run DataAnnotations validation programmatically:

```csharp
public static class ValidationHelper
{
    public static (bool IsValid, IReadOnlyList<ValidationResult> Errors) Validate<T>(
        T instance) where T : notnull
    {
        var results = new List<ValidationResult>();
        var context = new ValidationContext(instance);

        bool isValid = Validator.TryValidateObject(
            instance, context, results, validateAllProperties: true);

        return (isValid, results);
    }
}
```

**Critical:** Without `validateAllProperties: true`, `Validator.TryValidateObject` only checks `[Required]` attributes.

---

## Pattern 8: Validating File Uploads

```csharp
public class FileUploadValidator : AbstractValidator<FileUploadRequest>
{
    private readonly string[] _allowedExtensions = [".jpg", ".jpeg", ".png", ".pdf"];
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

    private bool BeValidSize(IFormFile file) => file.Length <= MaxFileSize;

    private bool BeValidExtension(IFormFile file)
    {
        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        return _allowedExtensions.Contains(extension);
    }
}
```

---

## Anti-Patterns

### Duplicate Validation

```csharp
// BAD: Validation in multiple places
if (string.IsNullOrEmpty(model.Email))
    ModelState.AddModelError("Email", "Required");

RuleFor(x => x.Email).NotEmpty(); // Duplicate!

// GOOD: Centralize validation in validators
```

### Silent Validation Failures

```csharp
// BAD: Ignoring validation results
catch (ValidationException)
{
    return Page();
}

// GOOD: Always add errors to ModelState
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
// BAD: Only client-side validation
public IActionResult OnPost(UserInput input)
{
    SaveToDatabase(input);
}

// GOOD: Server-side always validates
public IActionResult OnPost(UserInput input)
{
    if (!ModelState.IsValid)
        return Page();
    
    SaveToDatabase(input);
}
```

---

## Agent Gotchas

1. **Always pass `validateAllProperties: true`** to `Validator.TryValidateObject`.
2. **Options classes must use `{ get; set; }` not `{ get; init; }`** -- configuration binder needs to mutate properties.
3. **`IValidatableObject.Validate()` runs only after all attribute validations pass** -- do not rely on it for primary validation.
4. **Do not inject services into `ValidationAttribute` via constructor** -- use `validationContext.GetService<T>()` inside `IsValid()`.
5. **Register `IValidateOptions<T>` as singleton** -- the options validation infrastructure resolves validators as singletons.
6. **Do not forget `ValidateOnStart()`** -- without it, options validation only runs on first access.

---

## References

- [FluentValidation](https://docs.fluentvalidation.net/)
- [Model Validation in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/mvc/models/validation)
- [Data Annotations](https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.dataannotations)
- [IValidateOptions](https://learn.microsoft.com/en-us/dotnet/core/extensions/options#options-validation)
- [jQuery Validation](https://jqueryvalidation.org/)
