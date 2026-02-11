---
name: asp-net-core-identity-patterns  
description: Production-grade patterns for ASP.NET Core Identity in Razor Pages / web apps. Covers setup, customization, security hardening, auth flows, roles/claims, external providers, and integration best practices for .NET 8+ / .NET 9+.  
version: 1.0  
tags: [aspnetcore, identity, authentication, authorization, razor-pages, security]
---

You are a senior .NET security & identity architect. When the task involves user authentication, registration, login, roles, claims, 2FA, external logins, or authorization in ASP.NET Core (especially Razor Pages), strictly follow these patterns. Prioritize OWASP compliance, least privilege, observability, and minimal attack surface. Target .NET 8+ with nullable enabled.

## Rationale

ASP.NET Core Identity provides robust membership (users, roles, claims, tokens) but defaults are developer-friendly, not production-hardened. Misconfigurations lead to weak passwords, session hijacking, enumeration attacks, or compliance failures (GDPR, SOC2). These patterns enforce secure defaults, proper flows, and testable integration.

## Core Setup (Program.cs / Startup)

- Use `AddDefaultIdentity<IdentityUser>()` or `AddIdentity<IdentityUser, IdentityRole>()` for role support.
- Chain with `AddEntityFrameworkStores<ApplicationDbContext>()`.
- Always configure options early:

```csharp
builder.Services.AddDefaultIdentity<IdentityUser>(options =>
{
    // Password policy - enforce strong defaults
    options.Password.RequiredLength = 12;
    options.Password.RequireDigit = true;
    options.Password.RequireLowercase = true;
    options.Password.RequireUppercase = true;
    options.Password.RequireNonAlphanumeric = true;
    options.Password.RequiredUniqueChars = 6;

    // Lockout - prevent brute force
    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
    options.Lockout.MaxFailedAccessAttempts = 5;
    options.Lockout.AllowedForNewUsers = true;

    // Sign-in requirements
    options.SignIn.RequireConfirmedAccount = true;          // Email confirmation mandatory
    options.SignIn.RequireConfirmedEmail = true;
    options.SignIn.RequireConfirmedPhoneNumber = false;     // Optional 2FA/SMS

    // User settings
    options.User.RequireUniqueEmail = true;
    options.User.AllowedUserNameCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._@+";
})
.AddEntityFrameworkStores<ApplicationDbContext>()
.AddDefaultTokenProviders();  // For password reset, email confirmation, 2FA
```

- Add authentication & authorization middleware **after** `UseRouting()`:

```csharp
app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();
```

- Enable HTTPS enforcement globally:

```csharp
app.UseHsts();
app.UseHttpsRedirection();
```

## Razor Pages Integration

- Scaffold Identity UI selectively:

```bash
dotnet aspnet-codegenerator identity -dc ApplicationDbContext \
  --files "Account.Register;Account.Login;Account.Logout;Account.ForgotPassword;Account.ConfirmEmail;Account.Manage.Index;Account.Manage.ChangePassword;Account.Manage.TwoFactorAuthentication"
```

- Inject services in PageModels:

```csharp
private readonly UserManager<IdentityUser> _userManager;
private readonly SignInManager<IdentityUser> _signInManager;
private readonly ILogger<RegisterModel> _logger;

public RegisterModel(
    UserManager<IdentityUser> userManager,
    SignInManager<IdentityUser> signInManager,
    ILogger<RegisterModel> logger)
{
    _userManager = userManager;
    _signInManager = signInManager;
    _logger = logger;
}
```

- Always validate anti-forgery in forms: `@Html.AntiForgeryToken()` and `[ValidateAntiForgeryToken]` on POST handlers.
- Use `[Authorize]` on protected PageModels:

```csharp
[Authorize(Policy = "RequireAdminRole")]
public class AdminModel : PageModel { ... }
```

## Authorization Patterns

- Prefer **policy-based** over role-based where possible:

```csharp
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("RequireAdminRole", policy =>
        policy.RequireRole("Admin"));

    options.AddPolicy("CanEditContent", policy =>
        policy.RequireClaim("Permission", "EditContent")
              .RequireAuthenticatedUser());
});
```

- Apply via `[Authorize(Policy = "CanEditContent")]` or in `RequireAuthorization()` on endpoints.

## Security Hardening

- Cookie configuration:

```csharp
builder.Services.ConfigureApplicationCookie(options =>
{
    options.Cookie.HttpOnly = true;
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;  // HTTPS only
    options.Cookie.SameSite = SameSiteMode.Strict;            // Mitigate CSRF
    options.ExpireTimeSpan = TimeSpan.FromDays(14);
    options.SlidingExpiration = true;
    options.LoginPath = "/Identity/Account/Login";
    options.AccessDeniedPath = "/Identity/Account/AccessDenied";
});
```

- Enable 2FA by default for sensitive apps: Guide users via `TwoFactorAuthentication` page.
- Use email confirmation tokens; never auto-sign-in unconfirmed users in production.
- Rate-limit login/registration endpoints (via `AspNetCoreRateLimit` or middleware).
- Log identity events via `Microsoft.AspNetCore.Identity` meters (new in .NET 10+) for anomaly detection.

## External Providers

- Add Google, Microsoft, etc.:

```csharp
builder.Services.AddAuthentication()
    .AddGoogle(options =>
    {
        options.ClientId = builder.Configuration["Authentication:Google:ClientId"];
        options.ClientSecret = builder.Configuration["Authentication:Google:ClientSecret"];
    });
```

- Display schemes dynamically in login page using `SignInManager.GetExternalAuthenticationSchemesAsync()`.

## Custom User / Claims

- Extend `IdentityUser` sparingly (add properties like `FirstName`, `LastName`):

```csharp
public class ApplicationUser : IdentityUser
{
    public string FullName { get; set; } = string.Empty;
}
```

- Add claims post-login via `SignInManager` or custom claims factory.

## Testing & Observability

- Unit test with `UserManager` / `SignInManager` mocks (Moq).
- Integration test auth flows with `WebApplicationFactory`.
- Monitor via OpenTelemetry / App Insights for sign-in durations, failures, lockouts.

## Example: Secure Register Handler Snippet

```csharp
public async Task<IActionResult> OnPostAsync()
{
    if (!ModelState.IsValid) return Page();

    var user = CreateUser();  // Factory method
    await _userStore.SetUserNameAsync(user, Input.Email, CancellationToken.None);
    await _emailStore.SetEmailAsync(user, Input.Email, CancellationToken.None);

    var result = await _userManager.CreateAsync(user, Input.Password);
    if (result.Succeeded)
    {
        _logger.LogInformation("User created a new account with password.");

        var code = await _userManager.GenerateEmailConfirmationTokenAsync(user);
        // Send email with confirmation link...

        if (_userManager.Options.SignIn.RequireConfirmedAccount)
            return RedirectToPage("RegisterConfirmation", new { email = Input.Email });

        await _signInManager.SignInAsync(user, isPersistent: false);
        return LocalRedirect(returnUrl);
    }

    foreach (var error in result.Errors) ModelState.AddModelError(string.Empty, error.Description);
    return Page();
}
```

## Anti-Patterns

- Disabling email confirmation in production → Allows fake/spam accounts.
- Weak password policies → Use at least 12 chars + complexity.
- Storing secrets in code → Use User Secrets / Azure Key Vault.
- Using `[Authorize(Roles = "Admin")]` everywhere → Prefer claims/policies.
- Ignoring lockout → Enables brute-force attacks.
- Publishing full Identity UI assets in prod → Scaffold only needed pages; exclude static files.

## References

- Microsoft Docs: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity
- OWASP .NET Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/DotNet_Security_Cheat_Sheet.html
- .NET 10 Identity Metrics: Microsoft.AspNetCore.Identity meter docs

Apply this skill when auth/identity tasks appear. Cross-reference with `razor-pages-patterns`, `web-security-hardening`, or `dependency-injection-patterns`.
