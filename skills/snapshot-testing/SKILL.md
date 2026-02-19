---
name: snapshot-testing
description: Patterns for snapshot testing in .NET applications using Verify. Covers API responses, scrubbing non-deterministic values, custom converters, HTTP response testing, email templates, and CI/CD integration. Use when implementing snapshot tests for API responses, verifying UI component renders, detecting unintended changes in serialization output, or approving public API surfaces.
---

# Snapshot Testing with Verify

## When to Use This Skill

Use snapshot testing when:
- Verifying rendered output (HTML emails, reports, generated code)
- Approving public API surfaces for breaking change detection
- Testing HTTP response bodies and headers
- Validating serialization output
- Catching unintended changes in complex objects

---

## What is Snapshot Testing?

Snapshot testing captures output and compares it against a human-approved baseline:

1. **First run**: Test generates a `.received.` file with actual output
2. **Human review**: Developer approves it, creating a `.verified.` file
3. **Subsequent runs**: Test compares output against `.verified.` file
4. **Changes detected**: Test fails, diff tool shows differences for review

This catches **unintended changes** while allowing **intentional changes** through explicit approval.

---

## Setup

### Packages

```xml
<PackageReference Include="Verify.Xunit" Version="20.*" />
<PackageReference Include="Verify.Http" Version="6.*" />
```

### Module Initializer

Verify requires a one-time initialization per test assembly:

```csharp
// ModuleInitializer.cs
using System.Runtime.CompilerServices;

public static class ModuleInitializer
{
    [ModuleInitializer]
    public static void Init()
    {
        // Use source-file-relative paths for verified files
        VerifyBase.UseProjectRelativeDirectory("Snapshots");

        // Scrub common non-deterministic types globally
        VerifierSettings.ScrubMembersWithType<DateTime>();
        VerifierSettings.ScrubMembersWithType<DateTimeOffset>();
        VerifierSettings.ScrubMembersWithType<Guid>();

        // In CI, fail instead of launching diff tool
        if (Environment.GetEnvironmentVariable("CI") is not null)
        {
            DiffRunner.Disabled = true;
        }
    }
}
```

### Source Control

Add to `.gitignore`:

```gitignore
# Verify received files (test failures)
*.received.*
```

Add to `.gitattributes`:

```gitattributes
*.verified.txt text eol=lf
*.verified.xml text eol=lf
*.verified.json text eol=lf
*.verified.html text eol=lf
```

---

## Basic Usage

### Verifying Objects

```csharp
[UsesVerify]
public class OrderSerializationTests
{
    [Fact]
    public Task Serialize_CompletedOrder_MatchesSnapshot()
    {
        var order = new Order
        {
            Id = 1,
            CustomerId = "cust-123",
            Status = OrderStatus.Completed,
            Items =
            [
                new OrderItem("SKU-001", Quantity: 2, UnitPrice: 29.99m),
                new OrderItem("SKU-002", Quantity: 1, UnitPrice: 49.99m)
            ],
            Total = 109.97m
        };

        return Verify(order);
    }
}
```

Creates `OrderSerializationTests.Serialize_CompletedOrder_MatchesSnapshot.verified.txt`.

### Verifying Strings and Streams

```csharp
[Fact]
public Task RenderInvoice_MatchesExpectedHtml()
{
    var html = invoiceRenderer.Render(order);
    return Verify(html, extension: "html");
}

[Fact]
public Task ExportReport_MatchesExpectedXml()
{
    var stream = reportExporter.Export(report);
    return Verify(stream, extension: "xml");
}
```

---

## Scrubbing and Filtering

Non-deterministic values (dates, GUIDs, auto-incremented IDs) change between test runs. Scrubbing replaces them with stable placeholders.

### Built-In Scrubbers

```csharp
[Fact]
public Task CreateOrder_ScrubsNonDeterministicValues()
{
    var order = new Order
    {
        Id = Guid.NewGuid(),          // Scrubbed to Guid_1
        CreatedAt = DateTime.UtcNow,  // Scrubbed to DateTime_1
        TrackingNumber = Guid.NewGuid().ToString() // Scrubbed to Guid_2
    };

    return Verify(order);
}
```

Produces stable output:
```txt
{
  Id: Guid_1,
  CreatedAt: DateTime_1,
  TrackingNumber: Guid_2
}
```

### Custom Scrubbers

```csharp
[Fact]
public Task AuditLog_ScrubsTimestampsAndMachineNames()
{
    var log = auditService.GetRecentEntries();

    return Verify(log)
        .ScrubLinesWithReplace(line =>
            Regex.Replace(line, @"Machine:\s+\w+", "Machine: Scrubbed"))
        .ScrubLinesContaining("CorrelationId:");
}
```

### Ignoring Members

```csharp
[Fact]
public Task OrderSnapshot_IgnoresVolatileFields()
{
    var order = orderService.CreateOrder(request);

    return Verify(order)
        .IgnoreMember("CreatedAt")
        .IgnoreMember("UpdatedAt")
        .IgnoreMember("ETag");
}
```

### Scrubbing Inline Values

```csharp
[Fact]
public Task ApiResponse_ScrubsTokens()
{
    var response = authService.GenerateTokenResponse(user);

    return Verify(response)
        .ScrubLinesWithReplace(line =>
            Regex.Replace(line, @"Bearer [A-Za-z0-9\-._~+/]+=*", "Bearer {scrubbed}"));
}
```

---

## Verifying HTTP Responses

### Full HTTP Responses

```csharp
[UsesVerify]
public class OrdersApiSnapshotTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public OrdersApiSnapshotTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetOrders_ResponseMatchesSnapshot()
    {
        var response = await _client.GetAsync("/api/orders");
        await Verify(response);
    }
}
```

### Specific Response Parts

```csharp
[Fact]
public async Task CreateOrder_VerifyResponseBody()
{
    var response = await _client.PostAsJsonAsync("/api/orders", request);
    var body = await response.Content.ReadFromJsonAsync<OrderDto>();

    await Verify(body)
        .IgnoreMember("Id")
        .IgnoreMember("CreatedAt");
}
```

---

## Verifying Rendered Emails

Snapshot-test email templates by verifying the rendered HTML output:

```csharp
[UsesVerify]
public class EmailTemplateTests
{
    private readonly EmailRenderer _renderer = new();

    [Fact]
    public Task OrderConfirmation_MatchesSnapshot()
    {
        var model = new OrderConfirmationModel
        {
            CustomerName = "Alice Johnson",
            OrderNumber = "ORD-001",
            Items =
            [
                new("Widget A", Quantity: 2, Price: 29.99m),
                new("Widget B", Quantity: 1, Price: 49.99m)
            ],
            Total = 109.97m
        };

        var html = _renderer.RenderOrderConfirmation(model);
        return Verify(html, extension: "html");
    }

    [Fact]
    public Task PasswordReset_MatchesSnapshot()
    {
        var model = new PasswordResetModel
        {
            UserName = "alice",
            ResetLink = "https://example.com/reset?token=test-token"
        };

        var html = _renderer.RenderPasswordReset(model);

        return Verify(html, extension: "html")
            .ScrubLinesWithReplace(line =>
                Regex.Replace(line, @"token=[^""&]+", "token={scrubbed}"));
    }
}
```

**Benefits for email testing:**
- Catches CSS/layout regressions
- Detects broken template variables
- Visual review in diff tool
- Version control tracks email changes

---

## API Surface Approval

Prevent accidental breaking changes to public APIs:

```csharp
[Fact]
public Task ApprovePublicApi()
{
    var assembly = typeof(MyLibrary.PublicClass).Assembly;

    var publicApi = assembly.GetExportedTypes()
        .OrderBy(t => t.FullName)
        .Select(t => new
        {
            Type = t.FullName,
            Members = t.GetMembers(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
                .Where(m => m.DeclaringType == t)
                .OrderBy(m => m.Name)
                .Select(m => m.ToString())
        });

    return Verify(publicApi);
}
```

Or use the dedicated ApiApprover package:

```xml
<PackageReference Include="PublicApiGenerator" />
<PackageReference Include="Verify.Xunit" />
```

```csharp
[Fact]
public Task ApproveApi()
{
    var api = typeof(MyPublicClass).Assembly.GeneratePublicApi();
    return Verify(api);
}
```

Creates `.verified.txt` with full API surface - any change requires explicit approval.

---

## Custom Converters

Control how specific types are serialized for verification:

```csharp
public class MoneyConverter : WriteOnlyJsonConverter<Money>
{
    public override void Write(VerifyJsonWriter writer, Money value)
    {
        writer.WriteStartObject();
        writer.WriteMember(value, value.Amount, "Amount");
        writer.WriteMember(value, value.Currency.Code, "Currency");
        writer.WriteEndObject();
    }
}

public class AddressConverter : WriteOnlyJsonConverter<Address>
{
    public override void Write(VerifyJsonWriter writer, Address value)
    {
        // Single-line summary for compact snapshots
        writer.WriteValue($"{value.Street}, {value.City}, {value.State} {value.Zip}");
    }
}
```

Register in the module initializer:

```csharp
[ModuleInitializer]
public static void Init()
{
    VerifierSettings.AddExtraSettings(settings =>
    {
        settings.Converters.Add(new MoneyConverter());
        settings.Converters.Add(new AddressConverter());
    });
}
```

---

## Snapshot File Organization

### Unique Directory

Move verified files into a dedicated directory:

```csharp
[ModuleInitializer]
public static void Init()
{
    Verifier.DerivePathInfo(
        (sourceFile, projectDirectory, type, method) =>
            new PathInfo(
                directory: Path.Combine(projectDirectory, "Snapshots"),
                typeName: type.Name,
                methodName: method.Name));
}
```

### Parameterized Tests

For `[Theory]` tests, use `UseParameters()`:

```csharp
[Theory]
[InlineData("en-US")]
[InlineData("de-DE")]
[InlineData("ja-JP")]
public Task FormatCurrency_ByLocale_MatchesSnapshot(string locale)
{
    var formatted = currencyFormatter.Format(1234.56m, locale);
    return Verify(formatted).UseParameters(locale);
}
```

Creates separate files:
```
FormatCurrencyTests.FormatCurrency_ByLocale_MatchesSnapshot_locale=en-US.verified.txt
FormatCurrencyTests.FormatCurrency_ByLocale_MatchesSnapshot_locale=de-DE.verified.txt
FormatCurrencyTests.FormatCurrency_ByLocale_MatchesSnapshot_locale=ja-JP.verified.txt
```

---

## Workflow: Accepting Changes

### Diff Tool Integration

```csharp
[ModuleInitializer]
public static void Init()
{
    // Verify auto-detects installed diff tools
    // Override if needed:
    DiffTools.UseOrder(DiffTool.VisualStudioCode, DiffTool.Rider);
}
```

### CLI Acceptance

```bash
# Install the Verify CLI tool (one-time)
dotnet tool install -g verify.tool

# Accept all received files
verify accept

# Accept for a specific test project
verify accept --project tests/MyApp.Tests
```

### CI Behavior

```yaml
env:
  DiffEngine_Disabled: true
```

---

## CI/CD Integration

### GitHub Actions

```yaml
- name: Run tests
  run: dotnet test
  env:
    CI: true

- name: Upload snapshots on failure
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: snapshots
    path: |
      **/*.received.*
      **/*.verified.*
```

---

## When to Use Snapshot Testing

| Scenario | Use Snapshot Testing? | Why |
|----------|----------------------|-----|
| Rendered HTML/emails | Yes | Catches visual regressions |
| API surfaces | Yes | Prevents accidental breaks |
| Serialization output | Yes | Validates wire format |
| Complex object graphs | Yes | Easier than manual assertions |
| Simple value checks | No | Use regular assertions |
| Business logic | No | Use explicit assertions |
| Performance tests | No | Use benchmarks |

---

## Key Principles

- **Snapshot test complex outputs, not simple values.** If the expected value fits in a single `Assert.Equal`, prefer that.
- **Scrub all non-deterministic values.** Dates, GUIDs, timestamps must be scrubbed.
- **Commit `.verified.txt` files to source control.** Never add `.received.txt` files.
- **Review snapshot diffs carefully.** Accepting without review can silently approve regressions.
- **Use custom converters for domain readability.** Default serialization may be verbose.
- **Keep snapshots focused.** Use `IgnoreMember` to exclude volatile fields.

---

## Best Practices

### DO

```csharp
// Use descriptive test names - they become file names
[Fact]
public Task UserRegistration_WithValidData_ReturnsConfirmation()

// Scrub dynamic values consistently
VerifierSettings.ScrubMembersWithType<Guid>();

// Use extension parameter for non-text content
await Verify(html, extension: "html");

// Keep verified files in source control
git add *.verified.*
```

### DON'T

```csharp
// Don't verify random/dynamic data without scrubbing
var order = new Order { Id = Guid.NewGuid() };  // Fails every run!
await Verify(order);

// Don't commit .received files
git add *.received.*  // Wrong!

// Don't use for simple assertions
await Verify(result.Count);  // Just use Assert.Equal(5, result.Count)
```

---

## Agent Gotchas

1. **Do not forget `[UsesVerify]` on the test class.** Without it, `Verify()` calls fail at runtime.
2. **Do not commit `.received.txt` files.** Add `*.received.*` to `.gitignore`.
3. **Do not skip `UseParameters()` in parameterized tests.** All combinations write to the same file.
4. **Do not scrub values that are part of the contract.** Only scrub genuinely non-deterministic values.
5. **Do not use snapshot testing for rapidly evolving APIs.** Wait until the API stabilizes.
6. **Do not hardcode Verify package versions across different test frameworks.** Use version ranges (`20.*`).

---

## References

- [Verify GitHub repository](https://github.com/VerifyTests/Verify)
- [Verify documentation](https://github.com/VerifyTests/Verify/blob/main/docs/readme.md)
- [Verify.Http for HTTP response testing](https://github.com/VerifyTests/Verify.Http)
- [Scrubbing and filtering](https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md)
- [Custom converters](https://github.com/VerifyTests/Verify/blob/main/docs/converters.md)
- [DiffEngine (diff tool integration)](https://github.com/VerifyTests/DiffEngine)
- [ApiApprover](https://github.com/JakeGinnivan/ApiApprover)
