---
name: localization-globalization
description: Multi-language support, resource files, culture formatting, and globalization patterns for ASP.NET Core Razor Pages applications. Use when implementing multi-language support in ASP.NET Core applications, managing resource files for translations, or formatting dates, numbers, and currencies for different cultures.
---

## Rationale

Global applications require support for multiple languages, cultures, and formatting conventions. Poor localization implementation leads to maintenance nightmares, inconsistent user experiences, and hard-to-find bugs with dates, numbers, and currencies. These patterns provide a maintainable approach to building truly global Razor Pages applications.

## Patterns

### Pattern 1: Resource File Structure

Organize resources by feature with proper naming conventions and culture hierarchy.

```
/Pages
  /Shared
    _Layout.cshtml
    Resources/
      _Layout.resx          (default/en)
      _Layout.es.resx       (Spanish)
      _Layout.fr.resx       (French)
      _Layout.de.resx       (German)
  /Account
    Login.cshtml
    Login.cshtml.cs
    Resources/
      Login.resx
      Login.es.resx
      Login.fr.resx
  /Products
    Index.cshtml
    Resources/
      Index.resx
      Index.es.resx
/Resources  (Shared resources)
  SharedResources.resx
  SharedResources.es.resx
  ValidationMessages.resx
```

```csharp
// SharedResources.cs - Type-safe resource access
public class SharedResources
{
    // This class is just a marker for IStringLocalizer<SharedResources>
}

// Strongly-typed resources with code generator
public static class ResourceKeys
{
    public const string WelcomeMessage = "WelcomeMessage";
    public const string SaveButton = "SaveButton";
    public const string CancelButton = "CancelButton";
    public const string ErrorOccurred = "ErrorOccurred";
    public const string RequiredField = "RequiredField";
}
```

### Pattern 2: Localization Configuration

Configure request localization with proper culture detection and fallback.

```csharp
// Program.cs
var supportedCultures = new[]
{
    new CultureInfo("en-US"),
    new CultureInfo("en-GB"),
    new CultureInfo("es-ES"),
    new CultureInfo("es-MX"),
    new CultureInfo("fr-FR"),
    new CultureInfo("de-DE")
};

builder.Services.AddLocalization(options =>
{
    options.ResourcesPath = "Resources";
});

builder.Services.AddRequestLocalization(options =>
{
    options.DefaultRequestCulture = new RequestCulture("en-US");
    options.SupportedCultures = supportedCultures;
    options.SupportedUICultures = supportedCultures;
    
    // Culture detection order:
    // 1. Query string (?culture=es-ES)
    // 2. Cookie (.AspNetCore.Culture)
    // 3. Accept-Language header
    // 4. Default culture
    options.RequestCultureProviders = new List<IRequestCultureProvider>
    {
        new QueryStringRequestCultureProvider(),
        new CookieRequestCultureProvider(),
        new AcceptLanguageHeaderRequestCultureProvider()
    };
});

// Register view localization
builder.Services.AddRazorPages()
    .AddViewLocalization(LanguageViewLocationExpanderFormat.Suffix)
    .AddDataAnnotationsLocalization(options =>
    {
        options.DataAnnotationLocalizerProvider = (type, factory) =>
            factory.Create(typeof(SharedResources));
    });

// Middleware placement (must be before routing)
var app = builder.Build();
app.UseRequestLocalization();
app.UseRouting();
app.MapRazorPages();
```

### Pattern 3: Razor Pages Localization

Implement view and PageModel localization with proper resource injection.

```csharp
// PageModel with localization
public class ProductEditModel : PageModel
{
    private readonly IStringLocalizer<ProductEditModel> _localizer;
    private readonly IStringLocalizer<SharedResources> _sharedLocalizer;
    private readonly ILogger<ProductEditModel> _logger;

    public ProductEditModel(
        IStringLocalizer<ProductEditModel> localizer,
        IStringLocalizer<SharedResources> sharedLocalizer,
        ILogger<ProductEditModel> logger)
    {
        _localizer = localizer;
        _sharedLocalizer = sharedLocalizer;
        _logger = logger;
    }

    [BindProperty]
    public ProductInput Input { get; set; } = new();

    public string PageTitle => _localizer["EditProductTitle"];

    public async Task<IActionResult> OnPostAsync()
    {
        if (!ModelState.IsValid)
        {
            return Page();
        }

        try
        {
            await SaveProductAsync(Input);
            
            TempData["SuccessMessage"] = _localizer["ProductSaved"];
            return RedirectToPage("/Products/Index");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save product");
            ModelState.AddModelError(string.Empty, _sharedLocalizer["ErrorOccurred"]);
            return Page();
        }
    }
}

// View with localization
@page "{id:guid}"
@model ProductEditModel
@inject IStringLocalizer<SharedResources> SharedLocalizer
@inject IViewLocalizer ViewLocalizer

@{
    ViewData["Title"] = Model.PageTitle;
}

<h1>@ViewLocalizer["EditProductTitle"]</h1>

<form method="post">
    <div asp-validation-summary="ModelOnly" class="text-danger"></div>
    
    <div class="form-group">
        <label asp-for="Input.Name">@ViewLocalizer["ProductName"]</label>
        <input asp-for="Input.Name" class="form-control" 
               placeholder="@ViewLocalizer["NamePlaceholder"]" />
        <span asp-validation-for="Input.Name" class="text-danger"></span>
    </div>
    
    <div class="form-group">
        <label asp-for="Input.Price">@ViewLocalizer["Price"]</label>
        <input asp-for="Input.Price" class="form-control" 
               type="number" step="0.01" />
        <small class="form-text text-muted">
            @ViewLocalizer["PriceHelpText"]
        </small>
    </div>
    
    <button type="submit" class="btn btn-primary">
        @SharedLocalizer["SaveButton"]
    </button>
    <a asp-page="/Products/Index" class="btn btn-secondary">
        @SharedLocalizer["CancelButton"]
    </a>
</form>
```

### Pattern 4: Culture-Specific Formatting

Use culture-aware formatting for dates, numbers, and currencies.

```csharp
// Extension methods for consistent formatting
public static class FormattingExtensions
{
    public static string ToCurrency(this decimal amount, IFormatProvider? provider = null)
    {
        return amount.ToString("C", provider ?? CultureInfo.CurrentCulture);
    }

    public static string ToShortDate(this DateTime date, IFormatProvider? provider = null)
    {
        return date.ToString("d", provider ?? CultureInfo.CurrentCulture);
    }

    public static string ToLongDate(this DateTime date, IFormatProvider? provider = null)
    {
        return date.ToString("D", provider ?? CultureInfo.CurrentCulture);
    }

    public static string ToCompactNumber(this int number, IFormatProvider? provider = null)
    {
        return number.ToString("N0", provider ?? CultureInfo.CurrentCulture);
    }
}

// View usage
@inject IStringLocalizer<SharedResources> Localizer

<div class="product-details">
    <p>@Localizer["PriceLabel"]: @Model.Product.Price.ToCurrency()</p>
    <p>@Localizer["AvailableFrom"]: @Model.Product.AvailableDate.ToLongDate()</p>
    <p>@Localizer["StockQuantity"]: @Model.Product.Stock.ToCompactNumber()</p>
</div>

// Culture-specific validation messages
public class ProductInput
{
    [Required(ErrorMessageResourceName = "RequiredField", 
              ErrorMessageResourceType = typeof(SharedResources))]
    [StringLength(100, ErrorMessageResourceName = "MaxLength",
                  ErrorMessageResourceType = typeof(SharedResources))]
    public required string Name { get; set; }

    [Range(0.01, 999999.99, ErrorMessageResourceName = "InvalidPrice",
           ErrorMessageResourceType = typeof(SharedResources))]
    [DataType(DataType.Currency)]
    public decimal Price { get; set; }

    [DataType(DataType.Date)]
    [Display(ResourceType = typeof(SharedResources), Name = "AvailableDateLabel")]
    public DateTime AvailableDate { get; set; }
}
```

### Pattern 5: Language Switcher Implementation

Create a language switcher that persists culture selection.

```csharp
// Culture controller for switching languages
public class CultureController : Controller
{
    [HttpPost]
    public IActionResult SetCulture(string culture, string returnUrl)
    {
        if (!string.IsNullOrEmpty(culture))
        {
            Response.Cookies.Append(
                CookieRequestCultureProvider.DefaultCookieName,
                CookieRequestCultureProvider.MakeCookieValue(new RequestCulture(culture)),
                new CookieOptions { Expires = DateTimeOffset.UtcNow.AddYears(1) }
            );
        }

        return LocalRedirect(returnUrl ?? "/");
    }
}

// Language switcher partial view (_LanguageSwitcher.cshtml)
@inject IOptions<RequestLocalizationOptions> LocOptions

@{
    var requestCulture = Context.Features.Get<IRequestCultureFeature>()!;
    var cultureItems = LocOptions.Value.SupportedUICultures!
        .Select(c => new SelectListItem { 
            Value = c.Name, 
            Text = c.DisplayName,
            Selected = c.Name == requestCulture.RequestCulture.UICulture.Name
        })
        .ToList();
    var returnUrl = string.IsNullOrEmpty(Context.Request.Path) 
        ? "~/" 
        : $"~{Context.Request.Path.Value}{Context.Request.QueryString}";
}

<form asp-controller="Culture" asp-action="SetCulture" 
      asp-route-returnUrl="@returnUrl" method="post" 
      class="form-inline">
    <select name="culture" 
            class="form-control form-control-sm" 
            onchange="this.form.submit();"
            asp-for="@requestCulture.RequestCulture.UICulture.Name" 
            asp-items="cultureItems">
    </select>
</form>

// Include in _Layout.cshtml
<div class="navbar-nav">
    <partial name="_LanguageSwitcher" />
</div>
```

### Pattern 6: Pluralization and Complex Strings

Handle pluralization and parameterized strings correctly.

```csharp
// Using Humanizer for pluralization
public static class LocalizationHelpers
{
    public static string FormatItemsCount(IStringLocalizer localizer, int count)
    {
        var key = count switch
        {
            0 => "ItemsCountZero",
            1 => "ItemsCountOne",
            _ => "ItemsCountMany"
        };
        
        return localizer[key, count];
    }

    public static string FormatTimeRemaining(IStringLocalizer localizer, TimeSpan time)
    {
        if (time.TotalDays >= 1)
            return localizer["DaysRemaining", (int)time.TotalDays];
        if (time.TotalHours >= 1)
            return localizer["HoursRemaining", (int)time.TotalHours];
        if (time.TotalMinutes >= 1)
            return localizer["MinutesRemaining", (int)time.TotalMinutes];
        
        return localizer["LessThanMinute"];
    }
}

// Resource file entries
// ItemsCountZero: "No items"
// ItemsCountOne: "One item"
// ItemsCountMany: "{0} items"
// DaysRemaining: "{0} days remaining"
// HoursRemaining: "{0} hours remaining"
// MinutesRemaining: "{0} minutes remaining"
// LessThanMinute: "Less than a minute"

// View usage
<p>@LocalizationHelpers.FormatItemsCount(Localizer, Model.Items.Count)</p>
<p>@LocalizationHelpers.FormatTimeRemaining(Localizer, Model.TimeRemaining)</p>
```

### Pattern 7: RTL (Right-to-Left) Support

Support RTL languages like Arabic and Hebrew with proper CSS and layout.

```csharp
// View component for RTL detection
public class RtlLayoutViewComponent : ViewComponent
{
    private static readonly string[] RtlCultures = { "ar", "he", "fa", "ur" };

    public IViewComponentResult Invoke()
    {
        var currentCulture = CultureInfo.CurrentCulture.TwoLetterISOLanguageName;
        var isRtl = RtlCultures.Contains(currentCulture);
        
        return View(isRtl);
    }
}

// _Layout.cshtml modifications
@inject IViewLocalizer Localizer

@{
    var isRtl = CultureInfo.CurrentCulture.TextInfo.IsRightToLeft;
    var dir = isRtl ? "rtl" : "ltr";
}

<!DOCTYPE html>
<html lang="@CultureInfo.CurrentCulture.TwoLetterISOLanguageName" dir="@dir">
<head>
    @if (isRtl)
    {
        <link rel="stylesheet" href="~/css/bootstrap.rtl.min.css" />
        <link rel="stylesheet" href="~/css/site.rtl.css" />
    }
    else
    {
        <link rel="stylesheet" href="~/css/bootstrap.min.css" />
        <link rel="stylesheet" href="~/css/site.css" />
    }
</head>
<body>
    <!-- Content -->
</body>
</html>

// CSS with logical properties (works for both LTR and RTL)
.sidebar {
    margin-inline-start: 1rem; /* Replaces margin-left */
    padding-inline-end: 0.5rem; /* Replaces padding-right */
    border-inline-start: 1px solid #ddd;
}
```

## Anti-Patterns

```csharp
// ❌ BAD: Hard-coded strings
public string GetMessage() => "Hello, World!";

// ✅ GOOD: Use localizer
public string GetMessage() => _localizer["HelloWorld"];

// ❌ BAD: Concatenating strings for pluralization
var message = $"You have {count} item{(count != 1 ? "s" : "")}";

// ✅ GOOD: Use resource keys for each case
var message = count switch
{
    0 => _localizer["NoItems"],
    1 => _localizer["OneItem"],
    _ => _localizer["ManyItems", count]
};

// ❌ BAD: Formatting without culture
var price = $"${amount:F2}"; // Wrong currency symbol, wrong format

// ✅ GOOD: Culture-aware formatting
var price = amount.ToString("C", CultureInfo.CurrentCulture);

// ❌ BAD: Storing culture in session
HttpContext.Session.SetString("Culture", "es-ES"); // Not thread-safe

// ✅ GOOD: Use built-in cookie or query string providers
Response.Cookies.Append(
    CookieRequestCultureProvider.DefaultCookieName,
    CookieRequestCultureProvider.MakeCookieValue(new RequestCulture("es-ES")));

// ❌ BAD: Not providing fallback resources
// Only es-ES.resx exists, user requests es-MX

// ✅ GOOD: Provide neutral culture resources
// es.resx (neutral) + es-ES.resx (specific) + es-MX.resx (specific)

// ❌ BAD: Loading all resources on startup
foreach (var culture in supportedCultures)
{
    var resources = LoadResourcesForCulture(culture); // Expensive!
}

// ✅ GOOD: Let ASP.NET Core lazy-load resources as needed

// ❌ BAD: Mixing UI culture and data culture
Thread.CurrentThread.CurrentCulture = new CultureInfo("de-DE");    // Numbers/dates
Thread.CurrentThread.CurrentUICulture = new CultureInfo("es-ES");  // Resources

// ✅ GOOD: Usually keep them in sync unless you have specific requirements
var culture = new CultureInfo(userPreferredLanguage);
Thread.CurrentThread.CurrentCulture = culture;
Thread.CurrentThread.CurrentUICulture = culture;

// ❌ BAD: Not validating culture codes
public void SetCulture(string culture)
{
    CultureInfo.CurrentCulture = new CultureInfo(culture); // Throws on invalid!
}

// ✅ GOOD: Validate against supported cultures
public bool TrySetCulture(string cultureCode)
{
    var culture = supportedCultures.FirstOrDefault(c => 
        c.Name.Equals(cultureCode, StringComparison.OrdinalIgnoreCase));
    
    if (culture is null) return false;
    
    CultureInfo.CurrentCulture = culture;
    CultureInfo.CurrentUICulture = culture;
    return true;
}
```

## References

- [Globalization and localization in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/localization)
- [Resource files in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/resources)
- [CultureInfo class](https://learn.microsoft.com/en-us/dotnet/api/system.globalization.cultureinfo)
- [IStringLocalizer interface](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.localization.istringlocalizer)
- [Humanizer](https://github.com/Humanizr/Humanizer) - For pluralization and natural language
