# Bootstrap 5 + ASP.NET Core Razor Integration

## Table of Contents
- [Layout Structure](#layout-structure)
- [Tag Helpers with Bootstrap](#tag-helpers-with-bootstrap)
- [Form Validation Patterns](#form-validation-patterns)
- [Navigation with Tag Helpers](#navigation-with-tag-helpers)
- [Partial Views and Components](#partial-views-and-components)
- [Dark Mode Toggle in Razor](#dark-mode-toggle-in-razor)
- [Security Considerations](#security-considerations)
- [Complete Page Examples](#complete-page-examples)

## Layout Structure

### _Layout.cshtml with Bootstrap 5

```html
@using Microsoft.AspNetCore.Identity
<!doctype html>
<html lang="en" data-bs-theme="light">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@ViewData["Title"] - MyApp</title>
    <link rel="stylesheet" href="~/lib/bootstrap/dist/css/bootstrap.min.css" />
    <link rel="stylesheet" href="~/css/site.css" asp-append-version="true" />
    @await RenderSectionAsync("Styles", required: false)
</head>
<body>
    <header>
        <partial name="_NavbarPartial" />
    </header>

    <div class="container py-4">
        <main role="main">
            <partial name="_StatusMessagePartial" />
            @RenderBody()
        </main>
    </div>

    <footer class="container border-top py-3 mt-auto">
        <div class="row">
            <div class="col-md-6 text-body-secondary">&copy; @DateTime.Now.Year - MyApp</div>
            <div class="col-md-6 text-end">
                <a asp-page="/Privacy" class="text-body-secondary">Privacy</a>
            </div>
        </div>
    </footer>

    <script src="~/lib/bootstrap/dist/js/bootstrap.bundle.min.js"></script>
    <script src="~/lib/jquery-validation/dist/jquery.validate.min.js"></script>
    <script src="~/lib/jquery-validation-unobtrusive/jquery.validate.unobtrusive.min.js"></script>
    @await RenderSectionAsync("Scripts", required: false)
</body>
</html>
```

### _ViewImports.cshtml

```csharp
@using MyApp
@using MyApp.Pages
@namespace MyApp.Pages
@addTagHelper *, Microsoft.AspNetCore.Mvc.TagHelpers
```

## Tag Helpers with Bootstrap

### Form Controls

```html
<!-- Standard input with tag helpers -->
<div class="mb-3">
    <label asp-for="Input.Email" class="form-label"></label>
    <input asp-for="Input.Email" class="form-control" />
    <span asp-validation-for="Input.Email" class="text-danger"></span>
</div>

<!-- Select dropdown -->
<div class="mb-3">
    <label asp-for="Input.Category" class="form-label"></label>
    <select asp-for="Input.Category" asp-items="Model.Categories" class="form-select">
        <option value="">Choose...</option>
    </select>
    <span asp-validation-for="Input.Category" class="text-danger"></span>
</div>

<!-- Textarea -->
<div class="mb-3">
    <label asp-for="Input.Description" class="form-label"></label>
    <textarea asp-for="Input.Description" class="form-control" rows="4"></textarea>
    <span asp-validation-for="Input.Description" class="text-danger"></span>
</div>

<!-- Checkbox -->
<div class="mb-3 form-check">
    <input asp-for="Input.AgreeToTerms" class="form-check-input" />
    <label asp-for="Input.AgreeToTerms" class="form-check-label"></label>
    <span asp-validation-for="Input.AgreeToTerms" class="text-danger d-block"></span>
</div>

<!-- Radio buttons from enum -->
@foreach (var status in Enum.GetValues<OrderStatus>())
{
    <div class="form-check">
        <input class="form-check-input" type="radio"
               asp-for="Input.Status" value="@status" id="status-@status" />
        <label class="form-check-label" for="status-@status">@status</label>
    </div>
}
```

### Floating Labels with Tag Helpers

```html
<div class="form-floating mb-3">
    <input asp-for="Input.Email" class="form-control" placeholder="name@example.com" />
    <label asp-for="Input.Email"></label>
    <span asp-validation-for="Input.Email" class="text-danger"></span>
</div>
```

## Form Validation Patterns

### Server-Side + Bootstrap Validation Styles

PageModel:
```csharp
public class CreateModel : PageModel
{
    [BindProperty]
    public InputModel Input { get; set; } = new();

    public async Task<IActionResult> OnPostAsync()
    {
        if (!ModelState.IsValid)
            return Page();

        // process...
        return RedirectToPage("./Index");
    }

    public class InputModel
    {
        [Required(ErrorMessage = "Name is required")]
        [StringLength(100, MinimumLength = 2)]
        [Display(Name = "Full Name")]
        public string Name { get; set; } = string.Empty;

        [Required]
        [EmailAddress]
        [Display(Name = "Email Address")]
        public string Email { get; set; } = string.Empty;

        [Required]
        [Range(1, 1000, ErrorMessage = "Amount must be between 1 and 1000")]
        public decimal Amount { get; set; }
    }
}
```

Razor view with Bootstrap validation classes:
```html
<form method="post" novalidate>
    <div asp-validation-summary="ModelOnly" class="alert alert-danger" role="alert"></div>

    <div class="mb-3">
        <label asp-for="Input.Name" class="form-label"></label>
        <input asp-for="Input.Name"
               class="form-control @(ViewData.ModelState["Input.Name"]?.Errors.Count > 0 ? "is-invalid" : "")" />
        <span asp-validation-for="Input.Name" class="invalid-feedback"></span>
    </div>

    <div class="mb-3">
        <label asp-for="Input.Email" class="form-label"></label>
        <input asp-for="Input.Email"
               class="form-control @(ViewData.ModelState["Input.Email"]?.Errors.Count > 0 ? "is-invalid" : "")" />
        <span asp-validation-for="Input.Email" class="invalid-feedback"></span>
    </div>

    <button type="submit" class="btn btn-primary">
        <span class="spinner-border spinner-border-sm d-none" role="status" aria-hidden="true"></span>
        Submit
    </button>
</form>
```

### jQuery Validation Unobtrusive Integration

Add to `@section Scripts` to apply Bootstrap classes automatically:
```html
@section Scripts {
    <partial name="_ValidationScriptsPartial" />
    <script>
        // Override jQuery Validation to add Bootstrap classes
        const settings = $.data($('form')[0], 'validator')?.settings;
        if (settings) {
            settings.errorClass = 'is-invalid';
            settings.validClass = 'is-valid';
            settings.errorPlacement = function(error, element) {
                error.addClass('invalid-feedback');
                if (element.parent('.form-check').length) {
                    error.insertAfter(element.parent());
                } else if (element.parent('.input-group').length) {
                    error.insertAfter(element.parent());
                } else {
                    error.insertAfter(element);
                }
            };
            settings.highlight = function(element) {
                $(element).addClass('is-invalid').removeClass('is-valid');
            };
            settings.unhighlight = function(element) {
                $(element).removeClass('is-invalid').addClass('is-valid');
            };
        }
    </script>
}
```

## Navigation with Tag Helpers

### Navbar with Razor Tag Helpers

```html
<nav class="navbar navbar-expand-lg bg-body-tertiary sticky-top">
    <div class="container">
        <a class="navbar-brand" asp-page="/Index">
            <img src="~/images/logo.svg" alt="MyApp" width="30" height="24"
                 class="d-inline-block align-text-top">
            MyApp
        </a>
        <button class="navbar-toggler" type="button"
                data-bs-toggle="collapse" data-bs-target="#mainNav"
                aria-controls="mainNav" aria-expanded="false"
                aria-label="Toggle navigation">
            <span class="navbar-toggler-icon"></span>
        </button>
        <div class="collapse navbar-collapse" id="mainNav">
            <ul class="navbar-nav me-auto mb-2 mb-lg-0">
                <li class="nav-item">
                    <a class="nav-link @(ViewContext.RouteData.Values["page"]?.ToString() == "/Index" ? "active" : "")"
                       asp-page="/Index"
                       aria-current="@(ViewContext.RouteData.Values["page"]?.ToString() == "/Index" ? "page" : null)">
                        Home
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link @(ViewContext.RouteData.Values["page"]?.ToString()?.StartsWith("/Products") == true ? "active" : "")"
                       asp-page="/Products/Index">Products</a>
                </li>
                <li class="nav-item dropdown">
                    <a class="nav-link dropdown-toggle" href="#" role="button"
                       data-bs-toggle="dropdown" aria-expanded="false">Admin</a>
                    <ul class="dropdown-menu">
                        <li><a class="dropdown-item" asp-page="/Admin/Users">Users</a></li>
                        <li><a class="dropdown-item" asp-page="/Admin/Settings">Settings</a></li>
                        <li><hr class="dropdown-divider"></li>
                        <li><a class="dropdown-item" asp-page="/Admin/Logs">Logs</a></li>
                    </ul>
                </li>
            </ul>

            <!-- Auth-aware section -->
            @if (User.Identity?.IsAuthenticated == true)
            {
                <ul class="navbar-nav">
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle" href="#" role="button"
                           data-bs-toggle="dropdown">@User.Identity.Name</a>
                        <ul class="dropdown-menu dropdown-menu-end">
                            <li><a class="dropdown-item" asp-page="/Account/Profile">Profile</a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li>
                                <form method="post" asp-page="/Account/Logout">
                                    <button type="submit" class="dropdown-item">Sign out</button>
                                </form>
                            </li>
                        </ul>
                    </li>
                </ul>
            }
            else
            {
                <a class="btn btn-outline-primary me-2" asp-page="/Account/Login">Sign in</a>
                <a class="btn btn-primary" asp-page="/Account/Register">Sign up</a>
            }
        </div>
    </div>
</nav>
```

### Breadcrumbs

```html
<nav aria-label="breadcrumb">
    <ol class="breadcrumb">
        <li class="breadcrumb-item"><a asp-page="/Index">Home</a></li>
        <li class="breadcrumb-item"><a asp-page="/Products/Index">Products</a></li>
        <li class="breadcrumb-item active" aria-current="page">@Model.Product.Name</li>
    </ol>
</nav>
```

### Pagination

```html
@if (Model.TotalPages > 1)
{
    <nav aria-label="Page navigation">
        <ul class="pagination justify-content-center">
            <li class="page-item @(Model.CurrentPage == 1 ? "disabled" : "")">
                <a class="page-link" asp-page="./Index" asp-route-page="@(Model.CurrentPage - 1)">Previous</a>
            </li>
            @for (var i = 1; i <= Model.TotalPages; i++)
            {
                <li class="page-item @(i == Model.CurrentPage ? "active" : "")">
                    <a class="page-link" asp-page="./Index" asp-route-page="@i">@i</a>
                </li>
            }
            <li class="page-item @(Model.CurrentPage == Model.TotalPages ? "disabled" : "")">
                <a class="page-link" asp-page="./Index" asp-route-page="@(Model.CurrentPage + 1)">Next</a>
            </li>
        </ul>
    </nav>
}
```

## Partial Views and Components

### Status Message Partial (_StatusMessagePartial.cshtml)

```html
@{
    var statusMessage = TempData["StatusMessage"]?.ToString();
}
@if (!string.IsNullOrEmpty(statusMessage))
{
    var isError = statusMessage.StartsWith("Error");
    <div class="alert @(isError ? "alert-danger" : "alert-success") alert-dismissible fade show" role="alert">
        @statusMessage
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    </div>
}
```

### Confirmation Modal Partial

```html
<!-- _DeleteConfirmPartial.cshtml -->
@model (string ItemName, string DeleteUrl)
<div class="modal fade" id="deleteModal" tabindex="-1" aria-labelledby="deleteModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteModalLabel">Confirm Delete</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <p>Are you sure you want to delete <strong>@Model.ItemName</strong>?</p>
                <p class="text-danger mb-0">This action cannot be undone.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                <form method="post" asp-page-handler="Delete">
                    <button type="submit" class="btn btn-danger">Delete</button>
                </form>
            </div>
        </div>
    </div>
</div>
```

Usage:
```html
<button type="button" class="btn btn-outline-danger btn-sm"
        data-bs-toggle="modal" data-bs-target="#deleteModal">
    Delete
</button>
<partial name="_DeleteConfirmPartial" model='("Product X", "/Products/Delete")' />
```

### Loading Spinner Partial

```html
<!-- _LoadingPartial.cshtml -->
<div class="d-flex justify-content-center py-5" id="loading-spinner">
    <div class="spinner-border text-primary" role="status">
        <span class="visually-hidden">Loading...</span>
    </div>
</div>
```

## Dark Mode Toggle in Razor

### Toggle Button in Navbar

```html
<li class="nav-item dropdown">
    <button class="btn btn-link nav-link dropdown-toggle" data-bs-toggle="dropdown"
            aria-expanded="false" id="bd-theme">
        <span id="bd-theme-text">Theme</span>
    </button>
    <ul class="dropdown-menu dropdown-menu-end">
        <li><button type="button" class="dropdown-item" data-bs-theme-value="light">Light</button></li>
        <li><button type="button" class="dropdown-item" data-bs-theme-value="dark">Dark</button></li>
        <li><button type="button" class="dropdown-item" data-bs-theme-value="auto">Auto</button></li>
    </ul>
</li>
```

### Theme Toggle Script

Place at top of `<body>` to prevent flash:
```html
<script>
(() => {
    'use strict';
    const getStoredTheme = () => localStorage.getItem('theme');
    const setStoredTheme = theme => localStorage.setItem('theme', theme);
    const getPreferredTheme = () => {
        const stored = getStoredTheme();
        if (stored) return stored;
        return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    };
    const setTheme = theme => {
        if (theme === 'auto') {
            document.documentElement.setAttribute('data-bs-theme',
                window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
        } else {
            document.documentElement.setAttribute('data-bs-theme', theme);
        }
    };
    setTheme(getPreferredTheme());
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        const stored = getStoredTheme();
        if (stored !== 'light' && stored !== 'dark') setTheme(getPreferredTheme());
    });
    window.addEventListener('DOMContentLoaded', () => {
        document.querySelectorAll('[data-bs-theme-value]').forEach(toggle => {
            toggle.addEventListener('click', () => {
                const theme = toggle.getAttribute('data-bs-theme-value');
                setStoredTheme(theme);
                setTheme(theme);
            });
        });
    });
})();
</script>
```

## Security Considerations

### Anti-Forgery Tokens
ASP.NET Core auto-includes anti-forgery tokens in `<form method="post">` tag helper forms. For AJAX:
```html
@Html.AntiForgeryToken()
<script>
    const token = document.querySelector('input[name="__RequestVerificationToken"]').value;
    fetch('/api/data', {
        method: 'POST',
        headers: {
            'RequestVerificationToken': token,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
    });
</script>
```

### Content Security Policy (CSP) with Bootstrap
When using CSP headers, Bootstrap's inline styles require `nonce` or `unsafe-inline`. Prefer nonce:
```csharp
// In middleware or _Layout.cshtml
var nonce = Guid.NewGuid().ToString("N");
Context.Items["CspNonce"] = nonce;
```
```html
<link rel="stylesheet" href="~/lib/bootstrap/dist/css/bootstrap.min.css" nonce="@Context.Items["CspNonce"]" />
```

### Sanitize User Content
Razor auto-encodes output with `@`. For raw HTML (rare), use `@Html.Raw()` only with sanitized content. Never render untrusted input as raw HTML in Bootstrap components like toasts or modals.

## Complete Page Examples

### CRUD List Page

```html
@page
@model Products.IndexModel
@{ ViewData["Title"] = "Products"; }

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3 mb-0">Products</h1>
    <a asp-page="./Create" class="btn btn-primary">
        <i class="bi bi-plus-lg"></i> Add Product
    </a>
</div>

<!-- Search & Filter Bar -->
<div class="card mb-4">
    <div class="card-body">
        <form method="get" class="row g-3">
            <div class="col-md-4">
                <div class="input-group">
                    <input type="text" class="form-control" name="search"
                           value="@Model.SearchTerm" placeholder="Search products...">
                    <button class="btn btn-outline-secondary" type="submit">Search</button>
                </div>
            </div>
            <div class="col-md-3">
                <select name="category" class="form-select" onchange="this.form.submit()">
                    <option value="">All Categories</option>
                    @foreach (var cat in Model.Categories)
                    {
                        <option value="@cat.Id" selected="@(cat.Id == Model.SelectedCategory)">@cat.Name</option>
                    }
                </select>
            </div>
            <div class="col-md-3">
                <select name="sort" class="form-select" onchange="this.form.submit()">
                    <option value="name">Name A-Z</option>
                    <option value="name_desc">Name Z-A</option>
                    <option value="price">Price Low-High</option>
                    <option value="price_desc">Price High-Low</option>
                </select>
            </div>
        </form>
    </div>
</div>

<!-- Results Table -->
<div class="table-responsive">
    <table class="table table-striped table-hover align-middle">
        <thead class="table-dark">
            <tr>
                <th>Name</th>
                <th>Category</th>
                <th class="text-end">Price</th>
                <th class="text-center">Status</th>
                <th class="text-end">Actions</th>
            </tr>
        </thead>
        <tbody>
            @foreach (var item in Model.Products)
            {
                <tr>
                    <td>
                        <a asp-page="./Details" asp-route-id="@item.Id" class="text-decoration-none fw-semibold">
                            @item.Name
                        </a>
                    </td>
                    <td>@item.Category</td>
                    <td class="text-end">@item.Price.ToString("C")</td>
                    <td class="text-center">
                        <span class="badge @(item.IsActive ? "text-bg-success" : "text-bg-secondary")">
                            @(item.IsActive ? "Active" : "Inactive")
                        </span>
                    </td>
                    <td class="text-end">
                        <div class="btn-group btn-group-sm">
                            <a asp-page="./Edit" asp-route-id="@item.Id" class="btn btn-outline-primary">Edit</a>
                            <button type="button" class="btn btn-outline-danger"
                                    data-bs-toggle="modal" data-bs-target="#deleteModal-@item.Id">
                                Delete
                            </button>
                        </div>
                    </td>
                </tr>
            }
        </tbody>
    </table>
</div>

@if (!Model.Products.Any())
{
    <div class="text-center py-5 text-body-secondary">
        <p class="fs-5">No products found.</p>
        <a asp-page="./Create" class="btn btn-primary">Add your first product</a>
    </div>
}
```

### Create/Edit Form Page

```html
@page
@model Products.CreateModel
@{ ViewData["Title"] = "Create Product"; }

<nav aria-label="breadcrumb">
    <ol class="breadcrumb">
        <li class="breadcrumb-item"><a asp-page="/Index">Home</a></li>
        <li class="breadcrumb-item"><a asp-page="./Index">Products</a></li>
        <li class="breadcrumb-item active" aria-current="page">Create</li>
    </ol>
</nav>

<div class="row justify-content-center">
    <div class="col-lg-8">
        <div class="card shadow-sm">
            <div class="card-header">
                <h4 class="card-title mb-0">Create Product</h4>
            </div>
            <div class="card-body">
                <form method="post" enctype="multipart/form-data">
                    <div asp-validation-summary="ModelOnly" class="alert alert-danger"></div>

                    <div class="row mb-3">
                        <div class="col-md-8">
                            <label asp-for="Input.Name" class="form-label"></label>
                            <input asp-for="Input.Name" class="form-control" autofocus />
                            <span asp-validation-for="Input.Name" class="text-danger"></span>
                        </div>
                        <div class="col-md-4">
                            <label asp-for="Input.Price" class="form-label"></label>
                            <div class="input-group">
                                <span class="input-group-text">$</span>
                                <input asp-for="Input.Price" class="form-control" />
                            </div>
                            <span asp-validation-for="Input.Price" class="text-danger"></span>
                        </div>
                    </div>

                    <div class="mb-3">
                        <label asp-for="Input.Description" class="form-label"></label>
                        <textarea asp-for="Input.Description" class="form-control" rows="4"></textarea>
                        <span asp-validation-for="Input.Description" class="text-danger"></span>
                    </div>

                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label asp-for="Input.CategoryId" class="form-label"></label>
                            <select asp-for="Input.CategoryId" asp-items="Model.Categories" class="form-select">
                                <option value="">Select category...</option>
                            </select>
                            <span asp-validation-for="Input.CategoryId" class="text-danger"></span>
                        </div>
                        <div class="col-md-6">
                            <label asp-for="Input.Image" class="form-label"></label>
                            <input asp-for="Input.Image" class="form-control" type="file" accept="image/*" />
                            <span asp-validation-for="Input.Image" class="text-danger"></span>
                        </div>
                    </div>

                    <div class="form-check form-switch mb-4">
                        <input asp-for="Input.IsActive" class="form-check-input" />
                        <label asp-for="Input.IsActive" class="form-check-label"></label>
                    </div>

                    <div class="d-flex gap-2">
                        <button type="submit" class="btn btn-primary">Create Product</button>
                        <a asp-page="./Index" class="btn btn-outline-secondary">Cancel</a>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

@section Scripts {
    <partial name="_ValidationScriptsPartial" />
}
```
