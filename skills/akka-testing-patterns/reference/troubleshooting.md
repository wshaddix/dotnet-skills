---
name: akka-net-testing-troubleshooting
description: Troubleshooting guide and best practices for Akka.NET testing. Covers common patterns summary, anti-patterns to avoid, debugging tips, and CI/CD integration examples.
---

# Troubleshooting and Best Practices Reference

This reference document contains troubleshooting tips, anti-patterns to avoid, and CI/CD integration guidance for Akka.NET testing.

---

## Common Patterns Summary

| Pattern | Use Case |
|---------|----------|
| Basic Actor Test | Single actor with injected services |
| TestProbe | Verify actor sends messages to dependencies |
| Auto-Responder | Avoid `Ask` timeouts when testing |
| Persistent Actor | Test event sourcing and recovery |
| Cluster Sharding | Test sharding behavior locally |
| AwaitAssertAsync | Handle async operations in actors |
| Scenario Tests | End-to-end business workflows |

---

## Anti-Patterns to Avoid

### ❌ DON'T: Create Custom Test Base Classes

```csharp
// BAD: Custom base class for "DRY" setup
public abstract class BaseAkkaTest : TestKit
{
    protected IActorRef OrderActor { get; private set; }
    protected FakeOrderRepository FakeRepository { get; private set; }

    protected override void ConfigureAkka(...)
    {
        // Setup shared across all tests
    }
}

public class OrderActorTests : BaseAkkaTest
{
    // Now coupled to BaseAkkaTest setup
}
```

**Why it's bad:**
- Tight coupling between tests
- Hidden dependencies (what services are registered?)
- Difficult to customize per-test
- Violates principle of test isolation

**✅ DO: Use Method Overrides**

Each test class overrides `ConfigureServices()` and `ConfigureAkka()` with exactly what it needs.

### ❌ DON'T: Share State Between Tests

```csharp
// BAD: Reusing same actor instance across tests
public class OrderActorTests : TestKit
{
    private readonly IActorRef _orderActor;

    public OrderActorTests()
    {
        _orderActor = /* create once */;
    }

    [Fact] public void Test1() { /* uses _orderActor */ }
    [Fact] public void Test2() { /* uses _orderActor */ }
}
```

**Why it's bad:**
- Test1 and Test2 share state
- Test execution order matters
- Flaky tests due to side effects

**✅ DO: Use xUnit Class Fixtures or Get Fresh Actors**

```csharp
// GOOD: Each test gets clean ActorSystem
public class OrderActorTests : TestKit
{
    [Fact]
    public async Task Test1()
    {
        var actor = ActorRegistry.Get<OrderActor>(); // Fresh system
        // Test
    }

    [Fact]
    public async Task Test2()
    {
        var actor = ActorRegistry.Get<OrderActor>(); // Fresh system
        // Test
    }
}
```

### ❌ DON'T: Use Real External Dependencies

```csharp
// BAD: Using real database in tests
protected override void ConfigureServices(...)
{
    services.AddDbContext<OrderDbContext>(options =>
        options.UseSqlServer(connectionString)); // Real DB!
}
```

**✅ DO: Use Fakes or In-Memory Alternatives**

```csharp
// GOOD: Fake repository
protected override void ConfigureServices(...)
{
    services.AddSingleton<IOrderRepository>(_fakeRepository);
}
```

---

## Best Practices

1. **One test class per actor** - Keep tests focused
2. **Override ConfigureServices/ConfigureAkka** - Don't create base classes
3. **Use fakes, not mocks** - Simpler, more maintainable
4. **Test one actor at a time** - Use TestProbes for dependencies
5. **Match production patterns** - Same extension methods, different `AkkaExecutionMode`
6. **Use AwaitAssertAsync for async** - Prevents flaky tests
7. **Test recovery** - Kill and restart actors to verify persistence
8. **Scenario tests for workflows** - Test complete business flows end-to-end
9. **Keep tests fast** - In-memory persistence, no real databases
10. **Use meaningful names** - `Scenario_FirstTimePurchase_SuccessfulPayment`

---

## Debugging Tips

1. **Enable debug logging** - Pass `LogLevel.Debug` to TestKit constructor
2. **Use ITestOutputHelper** - See actor system logs in test output
3. **Inspect TestProbe** - Check `probe.Messages` to see what was sent
4. **Query actor state** - Add state query messages for debugging
5. **Use AwaitAssertAsync with logging** - See why assertions fail
6. **Check ActorRegistry** - Verify actors are registered correctly

```csharp
// Constructor with debug logging
public OrderActorTests(ITestOutputHelper output)
    : base(output: output, logLevel: LogLevel.Debug)
{
}

// Check what messages TestProbe received
[Fact]
public void DebugTest()
{
    // ... test code ...

    // Inspect all messages sent to probe
    _paymentProbe.Messages.Should().NotBeEmpty();
    foreach (var msg in _paymentProbe.Messages)
    {
        Output?.WriteLine($"Received: {msg}");
    }
}
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Akka.NET Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: 9.0.x

    - name: Restore dependencies
      run: dotnet restore

    - name: Build
      run: dotnet build --no-restore -c Release

    - name: Run Akka.NET tests
      run: |
        dotnet test tests/MyApp.Domain.Tests \
          --no-build \
          -c Release \
          --logger trx \
          --collect:"XPlat Code Coverage"

    - name: Publish test results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: "**/TestResults/*.trx"
```

---

## Additional Resources

- **Akka.NET Documentation**: https://getakka.net/
- **Akka.Hosting Documentation**: https://github.com/akkadotnet/Akka.Hosting
- **Petabridge Bootcamp**: https://petabridge.com/bootcamp/ (comprehensive Akka.NET training)
- **Akka.TestKit Guide**: https://getakka.net/articles/testing/testing-actor-systems.html
