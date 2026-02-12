---
name: dotnet-tunit-test
description: Guidelines for writing TUnit tests in .NET, including setup, assertions, async testing, and best practices. Use when writing unit tests with TUnit framework, setting up TUnit in a .NET project, or migrating from other test frameworks to TUnit.
---

# Testing with TUnit

## When to Use This Skill

Use this skill when:
- Creating a new TUnit test project or adding TUnit to an existing solution
- Writing unit, integration, or acceptance tests using TUnit
- Migrating tests from xUnit, NUnit, or MSTest to TUnit
- Configuring data-driven tests with `[Arguments]`, `[MethodDataSource]`, or `[ClassDataSource]`
- Setting up test lifecycle hooks (`[Before]`/`[After]`)
- Controlling parallelism with `[NotInParallel]`, `[DependsOn]`, or parallel groups
- Writing ASP.NET Core integration tests with `TUnit.AspNetCore`
- Configuring TUnit for CI/CD pipelines with coverage and TRX reports

---

## What is TUnit?

TUnit is a modern, source-generated testing framework for .NET built on the Microsoft Testing Platform. Key characteristics:

- **Source generated** - Tests are discovered at compile time, not via reflection
- **Parallel by default** - Tests run concurrently for speed
- **Async-first assertions** - All assertions must be awaited
- **New class instance per test** - Test classes are instantiated fresh for each test method
- **No `[TestClass]` attribute needed** - Only `[Test]` on methods
- **Native AOT and single-file support** - Works where reflection-based frameworks cannot
- **Built-in code coverage and TRX reports** - No need for Coverlet

---

## Installation

### From Template (Recommended)

```bash
dotnet new install TUnit.Templates
dotnet new TUnit -n "MyApp.Tests"
```

### Manual Setup

```bash
dotnet new console --name MyApp.Tests
cd MyApp.Tests
dotnet add package TUnit --prerelease
```

Remove any auto-generated `Program.cs` -- TUnit handles the entry point.

### Project File

```xml
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <OutputType>Exe</OutputType>
        <TargetFramework>net9.0</TargetFramework>
        <ImplicitUsings>enable</ImplicitUsings>
        <Nullable>enable</Nullable>
    </PropertyGroup>
    <ItemGroup>
        <PackageReference Include="TUnit" Version="*" />
    </ItemGroup>
</Project>
```

### CRITICAL: Do NOT Use These Packages

| Package | Why |
|---------|-----|
| `Microsoft.NET.Test.Sdk` | Breaks TUnit test discovery -- TUnit uses Microsoft.Testing.Platform, not VSTest |
| `coverlet.collector` / `coverlet.msbuild` | Incompatible with TUnit -- use the built-in `--coverage` flag instead |

### Global Usings

TUnit automatically provides global usings for `TUnit.Core`, `TUnit.Assertions`, and `TUnit.Assertions.Extensions`. You do not need explicit `using` statements in test files.

---

## Writing Tests

### Basic Test

```csharp
namespace MyApp.Tests;

public class CalculatorTests
{
    [Test]
    public async Task Add_TwoNumbers_ReturnsSum()
    {
        var result = 2 + 3;

        await Assert.That(result).IsEqualTo(5);
    }
}
```

### Test Method Signatures

```csharp
[Test]
public void SyncTest()           // Valid -- synchronous, no assertions
{
    var result = Calculate(2, 3);
}

[Test]
public async Task AsyncTest()    // Recommended -- required if using assertions
{
    await Assert.That(42).IsEqualTo(42);
}

// async void is NOT allowed -- compiler error
```

**Rule**: If you use `Assert.That(...)`, the test method **must** be `async Task` because assertions are awaitable.

---

## Assertions

All TUnit assertions follow the pattern `await Assert.That(actual).SomeCondition()`.

### Core Assertions

```csharp
// Equality
await Assert.That(result).IsEqualTo(5);
await Assert.That(result).IsNotEqualTo(0);

// Comparison
await Assert.That(score).IsGreaterThan(70);
await Assert.That(age).IsLessThanOrEqualTo(100);
await Assert.That(temp).IsBetween(20, 30);

// Boolean
await Assert.That(isValid).IsTrue();
await Assert.That(isDeleted).IsFalse();

// Null
await Assert.That(result).IsNotNull();
await Assert.That(optional).IsNull();

// Type
await Assert.That(obj).IsTypeOf<MyClass>();
```

### String Assertions

```csharp
await Assert.That(message).Contains("Hello");
await Assert.That(filename).StartsWith("test_");
await Assert.That(email).Matches(@"^[\w\.-]+@[\w\.-]+\.\w+$");
await Assert.That(input).IsNotEmpty();
```

### Collection Assertions

```csharp
await Assert.That(numbers).Contains(42);
await Assert.That(items).Count().IsEqualTo(5);
await Assert.That(list).IsNotEmpty();
await Assert.That(values).All(x => x > 0);
await Assert.That(numbers).IsEquivalentTo(new[] { 5, 4, 3, 2, 1 }); // order-independent
await Assert.That(numbers).IsInOrder();
```

### Exception Assertions

```csharp
// Basic exception testing
await Assert.That(() => int.Parse("not a number"))
    .Throws<FormatException>();

// Async exception testing
await Assert.That(async () => await FailingOperationAsync())
    .Throws<HttpRequestException>();

// Exact type (no subclasses)
await Assert.That(() => throw new ArgumentNullException())
    .ThrowsExactly<ArgumentNullException>();

// Exception message
await Assert.That(() => throw new InvalidOperationException("Operation failed"))
    .Throws<InvalidOperationException>()
    .WithMessage("Operation failed");

await Assert.That(() => throw new ArgumentException("The parameter 'userId' is invalid"))
    .Throws<ArgumentException>()
    .WithMessageContaining("userId");

// ArgumentException parameter name
await Assert.That(() => ValidateUser(null!))
    .Throws<ArgumentNullException>()
    .WithParameterName("user");

// Inner exceptions
await Assert.That(() => ThrowWithInner())
    .Throws<InvalidOperationException>()
    .WithInnerException()
    .Throws<FormatException>();

// No exception thrown
await Assert.That(() => int.Parse("42"))
    .ThrowsNothing();
```

### Chaining with And / Or

```csharp
await Assert.That(username)
    .IsNotNull()
    .And.IsNotEmpty()
    .And.Length().IsGreaterThan(3)
    .And.Length().IsLessThan(20);

await Assert.That(statusCode)
    .IsEqualTo(200)
    .Or.IsEqualTo(201)
    .Or.IsEqualTo(204);
```

### Assert.Multiple (Report All Failures)

```csharp
using (Assert.Multiple())
{
    await Assert.That(user.FirstName).IsEqualTo("John");
    await Assert.That(user.LastName).IsEqualTo("Doe");
    await Assert.That(user.Age).IsGreaterThan(18);
}
// All failures reported together, not just the first one
```

### Floating-Point Tolerance

```csharp
await Assert.That(3.14159).IsEqualTo(Math.PI).Within(0.001);
```

### CRITICAL: Always Await Assertions

```csharp
// WRONG -- assertion never executes, test always passes
Assert.That(result).IsEqualTo(5);

// CORRECT
await Assert.That(result).IsEqualTo(5);
```

TUnit includes a built-in analyzer that warns about unawaited assertions.

---

## Data-Driven Tests

### [Arguments] -- Compile-Time Constants

```csharp
[Test]
[Arguments(1, 1, 2)]
[Arguments(1, 2, 3)]
[Arguments(2, 2, 4)]
public async Task Add_ReturnsExpectedResult(int a, int b, int expected)
{
    await Assert.That(a + b).IsEqualTo(expected);
}
```

Supports metadata: `DisplayName`, `Categories`, `Skip`:

```csharp
[Test]
[Arguments("Chrome", "120")]
[Arguments("Safari", "17", Skip = "Safari not available in CI")]
public async Task BrowserTest(string browser, string version) { }
```

### [MethodDataSource] -- Dynamic/Complex Data

```csharp
public static class TestData
{
    public static IEnumerable<Func<(int A, int B, int Expected)>> AdditionCases()
    {
        yield return () => (1, 2, 3);
        yield return () => (2, 2, 4);
        yield return () => (5, 5, 10);
    }
}

public class MathTests
{
    [Test]
    [MethodDataSource(typeof(TestData), nameof(TestData.AdditionCases))]
    public async Task Add_WithData(int a, int b, int expected)
    {
        await Assert.That(a + b).IsEqualTo(expected);
    }
}
```

For reference types, return `Func<T>` (not `T`) to ensure each test gets a fresh instance.

### [ClassDataSource] -- Injectable Shared Resources

```csharp
public class TestWebServer : IAsyncInitializer, IAsyncDisposable
{
    public WebApplicationFactory<Program>? Factory { get; private set; }

    public async Task InitializeAsync()
    {
        Factory = new WebApplicationFactory<Program>();
        await Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        if (Factory != null) await Factory.DisposeAsync();
    }
}

[ClassDataSource<TestWebServer>(Shared = SharedType.PerTestSession)]
public class ApiTests(TestWebServer server)
{
    [Test]
    public async Task HealthCheck_ReturnsOk()
    {
        var client = server.Factory!.CreateClient();
        var response = await client.GetAsync("/health");

        await Assert.That(response.IsSuccessStatusCode).IsTrue();
    }
}
```

**SharedType options:**
- `None` (default) -- new instance per test
- `PerClass` -- shared within the test class
- `PerAssembly` -- shared within the assembly
- `PerTestSession` -- single instance for entire test run
- `Keyed` -- shared among tests with the same `Key`

---

## Test Lifecycle

### Instance Per Test

TUnit creates a **new instance** of the test class for each test method. Instance fields are never shared between tests.

```csharp
public class MyTests
{
    private int _value;

    [Test, NotInParallel]
    public void Test1() { _value = 99; }

    [Test, NotInParallel]
    public async Task Test2()
    {
        // _value is 0 here -- different instance!
        await Assert.That(_value).IsEqualTo(0);
    }
}
```

Use `static` fields if you intentionally need shared state.

### Setup Hooks -- [Before]

```csharp
public class DatabaseTests
{
    private TestDatabase? _database;

    [Before(Test)]    // Instance method, runs before each test
    public async Task SetupDatabase()
    {
        _database = await TestDatabase.CreateAsync();
    }

    [Before(Class)]   // Must be static, runs once before all tests in class
    public static async Task ClassSetup()
    {
        await GlobalResource.InitializeAsync();
    }

    [Before(Assembly)] // Must be static, runs once before all tests in assembly
    public static async Task AssemblySetup() { }
}
```

### Cleanup Hooks -- [After]

```csharp
public class DatabaseTests
{
    [After(Test)]     // Instance method, runs after each test
    public async Task Cleanup()
    {
        if (_database != null) await _database.DisposeAsync();
    }

    [After(Class)]    // Must be static, runs once after all tests in class
    public static async Task ClassCleanup() { }
}
```

Every `[After]` method runs even if a previous one fails. Exceptions are aggregated.

### Hook Levels

| Level | Scope | Static? |
|-------|-------|---------|
| `[Before(Test)]` / `[After(Test)]` | Each test | Instance |
| `[Before(Class)]` / `[After(Class)]` | Once per class | Static |
| `[Before(Assembly)]` / `[After(Assembly)]` | Once per assembly | Static |
| `[Before(TestSession)]` / `[After(TestSession)]` | Once per test run | Static |

### Global Hooks -- [BeforeEvery] / [AfterEvery]

Place in a `GlobalHooks.cs` at the project root:

```csharp
public static class GlobalHooks
{
    [BeforeEvery(Test)]
    public static void BeforeEachTest(TestContext context)
    {
        Console.WriteLine($"Starting: {context.Metadata.TestName}");
    }

    [AfterEvery(Test)]
    public static async Task AfterEachTest(TestContext context)
    {
        if (context.Execution.Result?.State == TestState.Failed)
        {
            await CaptureScreenshotAsync();
        }
    }
}
```

### Hook Parameters

Hooks can accept context and cancellation token:

```csharp
[Before(Test)]
public async Task Setup(TestContext context, CancellationToken ct)
{
    Console.WriteLine($"Setting up: {context.Metadata.TestName}");
    await SomeOperation(ct);
}
```

---

## Parallelism

### Default: Tests Run in Parallel

TUnit runs all tests concurrently by default. Write independent, stateless tests.

### [NotInParallel] -- Disable for Specific Tests

```csharp
[Test, NotInParallel]
public async Task ModifiesSharedResource() { }
```

### Constraint Keys -- Parallel Groups

```csharp
// These two won't run in parallel with each other (shared key)
[Test, NotInParallel("DatabaseTest")]
public async Task DbTest1() { }

[Test, NotInParallel("DatabaseTest")]
public async Task DbTest2() { }

// This can still run in parallel with the above
[Test, NotInParallel("FileTest")]
public async Task FileTest1() { }
```

### [DependsOn] -- Order with Parallelism

```csharp
[Test]
public async Task Step1_CreateUser() { }

[Test]
[DependsOn(nameof(Step1_CreateUser))]
public async Task Step2_UpdateUser() { }

[Test]
[DependsOn(nameof(Step2_UpdateUser))]
public async Task Step3_DeleteUser() { }
// Other unrelated tests still run in parallel
```

### Disable All Parallelism

```csharp
[assembly: NotInParallel]
```

### Limit Concurrent Tests (CLI)

```bash
dotnet run -c Release --maximum-parallel-tests 8
```

---

## Dependency Injection

```csharp
public class MicrosoftDiDataSourceAttribute
    : DependencyInjectionDataSourceAttribute<IServiceScope>
{
    private static readonly IServiceProvider ServiceProvider = CreateProvider();

    public override IServiceScope CreateScope(DataGeneratorMetadata metadata)
        => ServiceProvider.CreateScope();

    public override object? Create(IServiceScope scope, Type type)
        => scope.ServiceProvider.GetService(type);

    private static IServiceProvider CreateProvider()
        => new ServiceCollection()
            .AddSingleton<IMyService, MyService>()
            .AddTransient<IRepository, Repository>()
            .BuildServiceProvider();
}

[MicrosoftDiDataSource]
public class ServiceTests(IMyService service, IRepository repo)
{
    [Test]
    public async Task ServiceWorks()
    {
        var result = await service.DoWorkAsync();
        await Assert.That(result).IsNotNull();
    }
}
```

---

## ASP.NET Core Integration Testing

Install the `TUnit.AspNetCore` package:

```bash
dotnet add package TUnit.AspNetCore
```

### Factory + Base Class Pattern

```csharp
using TUnit.AspNetCore;

public class AppFactory : TestWebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "ConnectionStrings:Default", "..." }
            });
        });
    }
}

public abstract class IntegrationTestBase : WebApplicationTest<AppFactory, Program> { }
```

### Writing Integration Tests

```csharp
public class TodoApiTests : IntegrationTestBase
{
    [Test]
    public async Task GetTodos_ReturnsOk()
    {
        var client = Factory.CreateClient();
        var response = await client.GetAsync("/todos");

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.OK);
    }

    // Override per-test services
    protected override void ConfigureTestServices(IServiceCollection services)
    {
        services.ReplaceService<IEmailService>(new FakeEmailService());
    }

    // Override per-test configuration
    protected override void ConfigureTestConfiguration(IConfigurationBuilder config)
    {
        config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            { "Feature:Enabled", "true" }
        });
    }
}
```

### Test Isolation with Shared Containers

Each test gets a unique ID for resource isolation:

```csharp
public abstract class DatabaseTestBase : IntegrationTestBase
{
    protected string TableName { get; private set; } = null!;

    protected override async Task SetupAsync()
    {
        TableName = GetIsolatedName("todos"); // "Test_42_todos"
        await CreateTableAsync(TableName);
    }

    protected override void ConfigureTestConfiguration(IConfigurationBuilder config)
    {
        config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            { "Database:TableName", TableName }
        });
    }

    [After(HookType.Test)]
    public async Task Cleanup() => await DropTableAsync(TableName);
}
```

---

## Running Tests

### Command Line

```bash
# Preferred -- easier flag passing
dotnet run -c Release

# With coverage and TRX report
dotnet run -c Release --coverage --report-trx

# Using dotnet test (flags go after --)
dotnet test -c Release -- --coverage --report-trx
```

### IDE Support

| IDE | Setting Required |
|-----|-----------------|
| **Visual Studio** | Enable "Use testing platform server mode" in Tools > Manage Preview Features |
| **Rider** | Enable "Testing Platform support" in Settings > Build, Execution, Deployment > Unit Testing > Testing Platform |
| **VS Code** | Install C# Dev Kit, enable "Dotnet > Test Window > Use Testing Platform Protocol" |

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-dotnet@v4
      with:
        dotnet-version: 9.0.x
    - run: dotnet restore
    - run: dotnet build --no-restore -c Release
    - run: dotnet run --project tests/MyApp.Tests -c Release --no-build -- --report-trx --coverage
    - uses: actions/upload-artifact@v4
      if: always()
      with:
        name: test-results
        path: |
          **/TestResults/*.trx
          **/TestResults/**/coverage.cobertura.xml
```

---

## Test Naming Conventions

Use descriptive names: `Method_Scenario_ExpectedBehavior`

```csharp
[Test]
public async Task CalculateTotal_WithDiscount_ReturnsReducedPrice() { }

[Test]
public async Task CreateUser_WithDuplicateEmail_ThrowsConflictException() { }
```

---

## Test Organization

Mirror production code structure:

```
MyApp/
  Services/
    OrderService.cs
MyApp.Tests/
  Services/
    OrderServiceTests.cs
```

Use nested classes to group related scenarios:

```csharp
public class OrderServiceTests
{
    public class CreateOrder
    {
        [Test]
        public async Task WithValidData_ReturnsOrder() { }

        [Test]
        public async Task WithMissingCustomer_ThrowsException() { }
    }

    public class CancelOrder
    {
        [Test]
        public async Task WithPendingOrder_Succeeds() { }
    }
}
```

---

## Common Mistakes

### Forgetting to Await Assertions

```csharp
// WRONG -- silently passes
Assert.That(result).IsEqualTo(5);

// CORRECT
await Assert.That(result).IsEqualTo(5);
```

### Using Instance State Between Tests

```csharp
// WRONG -- each test gets a new class instance
private int _counter;

[Test, NotInParallel]
public void Increment() { _counter++; }

[Test, NotInParallel]
public async Task Check()
{
    await Assert.That(_counter).IsEqualTo(1); // Fails -- _counter is 0
}
```

### Using Microsoft.NET.Test.Sdk

This package is for VSTest-based frameworks. TUnit uses Microsoft.Testing.Platform. Including it will break test discovery.

### Relying on Test Execution Order

Tests run in parallel by default. Never assume order unless you use `[DependsOn]` or `[NotInParallel(Order = N)]`.

### Over-Mocking

```csharp
// BAD -- mock everything
var mockLogger = new Mock<ILogger>();
var mockValidator = new Mock<IValidator>();
var mockCalculator = new Mock<IPriceCalculator>();

// BETTER -- only mock external dependencies
var logger = NullLogger.Instance;
var validator = new OrderValidator();            // Real, fast
var mockRepository = new Mock<IOrderRepository>(); // Mock database
```

---

## Best Practices Summary

| Practice | Why |
|----------|-----|
| Always `await` assertions | Unawaited assertions silently pass |
| Use `async Task` for test methods | Required by TUnit's assertion model |
| One logical behavior per test | Keeps tests focused and failure messages clear |
| Use `Assert.Multiple` for related checks | See all failures at once |
| Prefer `[DependsOn]` over `[NotInParallel(Order)]` | Maintains parallelism for unrelated tests |
| Use `[ClassDataSource]` for expensive resources | Share across tests with `SharedType.PerTestSession` |
| Test behavior, not implementation | Avoid brittle mock-verification tests |
| Use `GetIsolatedName()` in integration tests | Ensures parallel test isolation |
| Place `[BeforeEvery]`/`[AfterEvery]` in `GlobalHooks.cs` | Easy to find global hooks |
| Do not install `Microsoft.NET.Test.Sdk` | Breaks TUnit test discovery |

---

## Resources

- **TUnit Docs**: https://tunit.dev/docs/intro
- **GitHub**: https://github.com/thomhurst/TUnit
- **NuGet**: https://www.nuget.org/packages/TUnit
- **TUnit.AspNetCore**: https://www.nuget.org/packages/TUnit.AspNetCore
- **Migration from xUnit**: https://tunit.dev/docs/migration/xunit
- **Migration from NUnit**: https://tunit.dev/docs/migration/nunit
- **Migration from MSTest**: https://tunit.dev/docs/migration/mstest
