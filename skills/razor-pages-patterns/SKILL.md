---
name: Razor Pages Patterns
description: Best practices for building production-grade ASP.NET Core Razor Pages applications. Focuses on structure, lifecycle, binding, validation, security, and maintainability in web apps using Razor Pages as the primary UI framework.
version: 1.0
last-updated: 2026-02-11
tags: [aspnetcore, razor-pages, web-development, patterns]
---

You are a senior ASP.NET Core architect specializing in Razor Pages. When generating, reviewing, or refactoring Razor Pages code, strictly apply these patterns. Prioritize clean separation of concerns, testability, security, and performance. Target .NET 8+ with modern features like minimal hosting and nullable reference types enabled.

### Rationale
Razor Pages provide a page-focused model for web apps, simplifying MVC by combining controllers and views into PageModels. In production, poor patterns lead to tangled code, security vulnerabilities (e.g., CSRF), validation gaps, and scalability issues. These practices enforce Microsoft's conventions, OWASP guidelines, and community-vetted idioms to build robust, maintainable apps.

### Best Practices
1. **Project Structure**  
   - Organize pages in `/Pages` folder with logical subfolders (e.g., `/Pages/Account`, `/Pages/Admin`).  
   - Use `_ViewImports.cshtml` for global tag helpers, using directives, and model imports.  
   - Enable nullable reference types project-wide (`<Nullable>enable</Nullable>`) to catch nulls early.  
   - Avoid mixing Razor Pages with controllers/APIs in the same project unless it's a hybrid app; separate concerns via areas or microservices.

2. **PageModel Design**  
   - Keep PageModels lean: inject dependencies (e.g., services, DbContexts) via constructor.  
   - Use handler methods for actions (e.g., `OnGetAsync`, `OnPostAsync`). Limit to 1-2 handlers per page for simplicity.  
   - Prefer async handlers for I/O-bound ops (e.g., DB calls).  
   - Bind properties with `[BindProperty]` sparingly; use explicit model binding for complex forms to avoid over-posting attacks.

3. **Model Binding and Validation**  
   - Use data annotations on bound models (e.g., `[Required]`, `[StringLength]`, `[EmailAddress]`).  
   - Validate on server-side always; client-side (via jQuery Validation) is optional enhancement.  
   - Check `ModelState.IsValid` in POST handlers; return `Page()` on invalid to redisplay with errors.  
   - For custom validation, implement `IValidatableObject` or use FluentValidation integration.

4. **Routing and Navigation**  
   - Use `@page` directive with route templates (e.g., `@page "/{id:int}"`).  
   - Leverage tag helpers like `<a asp-page="/Index">` for type-safe links.  
   - Handle slugs/SEO-friendly URLs with custom route handlers if needed.  
   - Redirect with `RedirectToPage` for PRG (Post-Redirect-Get) pattern to prevent duplicate submissions.

5. **Views and Razor Syntax**  
   - Keep .cshtml files view-only: no business logic; use partials (`_Partial.cshtml`) for reusable UI.  
   - Employ tag helpers (e.g., `<input asp-for="Model.Property" />`) for HTML generation.  
   - Use sections (`@section Scripts { ... }`) for page-specific JS/CSS.  
   - Enable bundling/minification in production via `webOptimizer` or built-in middleware.

6. **Security Practices**  
   - Always include anti-forgery tokens: `@Html.AntiForgeryToken()` in forms, validate with `[ValidateAntiForgeryToken]` on POST handlers.  
   - Apply `[Authorize]` on PageModels for auth; use policies for fine-grained access.  
   - Sanitize inputs to prevent XSS; Razor escapes by default, but validate user-generated content.  
   - Enforce HTTPS with `app.UseHsts()` and `app.UseHttpsRedirection()`.

7. **Error Handling and Logging**  
   - Use `app.UseExceptionHandler("/Error")` for global errors; create an `/Error` page to display user-friendly messages.  
   - Log exceptions with injected `ILogger<PageModel>`.  
   - Differentiate dev vs. prod: show stack traces only in dev with `app.UseDeveloperExceptionPage()`.  
   - Return status codes appropriately (e.g., `NotFound()`, `BadRequest()`).

8. **Performance and Scalability**  
   - Use output caching with `[ResponseCache]` on pages.  
   - Avoid session state if possible; prefer TempData for one-time messages.  
   - Optimize DB access: eager-load related data, use projections.  
   - Profile with tools like dotnet-trace or MiniProfiler.

9. **Testing**  
   - Unit test PageModels by mocking dependencies (e.g., with Moq).  
   - Integration test with `WebApplicationFactory` to simulate requests.  
   - UI test forms/submissions with Playwright or Selenium.  
   - Aim for 80%+ coverage on handlers and models.

### Examples

**Well-Structured PageModel (Index.cshtml.cs):**
```csharp
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using System.ComponentModel.DataAnnotations;

namespace MyApp.Pages
{
    public class IndexModel : PageModel
    {
        private readonly ILogger<IndexModel> _logger;
        private readonly IMyService _service;

        public IndexModel(ILogger<IndexModel> logger, IMyService service)
        {
            _logger = logger;
            _service = service;
        }

        [BindProperty]
        public InputModel Input { get; set; } = new();

        public string Message { get; set; } = string.Empty;

        public async Task OnGetAsync()
        {
            Message = await _service.GetWelcomeMessageAsync();
        }

        public async Task<IActionResult> OnPostAsync()
        {
            if (!ModelState.IsValid)
            {
                return Page();
            }

            try
            {
                await _service.ProcessInputAsync(Input);
                return RedirectToPage("/Success");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing input");
                ModelState.AddModelError(string.Empty, "An error occurred.");
                return Page();
            }
        }

        public class InputModel
        {
            [Required(ErrorMessage = "Name is required")]
            [StringLength(100)]
            public string Name { get; set; } = string.Empty;
        }
    }
}
```

**Corresponding Razor View (Index.cshtml):**
```csharp
@page
@model IndexModel
@{
    ViewData["Title"] = "Home page";
}

<div class="text-center">
    <h1 class="display-4">Welcome</h1>
    <p>@Model.Message</p>
</div>

<form method="post">
    <div asp-validation-summary="ModelOnly" class="text-danger"></div>
    <div class="form-group">
        <label asp-for="Input.Name" class="control-label"></label>
        <input asp-for="Input.Name" class="form-control" />
        <span asp-validation-for="Input.Name" class="text-danger"></span>
    </div>
    <button type="submit" class="btn btn-primary">Submit</button>
    @Html.AntiForgeryToken()
</form>
```

## Anti-Patterns

- God PageModels: Cramming multiple unrelated handlers into one model → Split into separate pages.
- Magic Strings: Hardcoding routes/URLs → Use asp-page tag helpers or IUrlHelper.
- Ignoring Validation: Skipping ModelState.IsValid → Always validate to prevent invalid data.
- Sync Over Async: Using sync DB calls in handlers → Go async to avoid thread pool starvation.
- No Logging: Swallowing exceptions silently → Always log with context.
- Over-Posting: Binding entire models without whitelisting → Use [Bind("Property1,Property2")] or view models.

## References

- Microsoft Docs: https://learn.microsoft.com/en-us/aspnet/core/razor-pages/
- OWASP Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/DotNet_Security_Cheat_Sheet.html
- Community: https://github.com/dotnet/aspnetcore (samples)
- Tools: FluentValidation, MiniProfiler, xUnit for tests.

Apply this skill selectively: Only when the task involves Razor Pages. Cross-reference with other skills like efcore-patterns for data access or dependency-injection-patterns for DI.