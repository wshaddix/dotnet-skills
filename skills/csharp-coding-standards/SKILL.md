---
name: modern-csharp-coding-standards
description: Write modern, high-performance C# code using records, pattern matching, value objects, async/await, Span<T>/Memory<T>, and best-practice API design patterns. Emphasizes functional-style programming with C# 12+ features. Use when writing new C# code or refactoring existing code, designing public APIs for libraries or services, optimizing performance-critical code paths, or building async/await-heavy applications.
---

# Modern C# Coding Standards

## When to Use This Skill

Use this skill when:
- Writing new C# code or refactoring existing code
- Designing public APIs for libraries or services
- Optimizing performance-critical code paths
- Implementing domain models with strong typing
- Building async/await-heavy applications
- Working with binary data, buffers, or high-throughput scenarios

## Core Principles

1. **Immutability by Default** - Use `record` types and `init`-only properties
2. **Type Safety** - Leverage nullable reference types and value objects
3. **Modern Pattern Matching** - Use `switch` expressions and patterns extensively
4. **Async Everywhere** - Prefer async APIs with proper cancellation support
5. **Zero-Allocation Patterns** - Use `Span<T>` and `Memory<T>` for performance-critical code
6. **API Design** - Accept abstractions, return appropriately specific types
7. **Composition Over Inheritance** - Avoid abstract base classes, prefer composition
8. **Value Objects as Structs** - Use `readonly record struct` for value objects

---

## Naming Conventions

### General Rules

| Element | Convention | Example |
|---------|-----------|---------|
| Namespaces | PascalCase, dot-separated | `MyCompany.MyProduct.Core` |
| Classes, Records, Structs | PascalCase | `OrderService`, `OrderSummary` |
| Interfaces | `I` + PascalCase | `IOrderRepository` |
| Methods | PascalCase | `GetOrderAsync` |
| Properties | PascalCase | `OrderDate` |
| Events | PascalCase | `OrderCompleted` |
| Public constants | PascalCase | `MaxRetryCount` |
| Private fields | `_camelCase` | `_orderRepository` |
| Parameters, locals | camelCase | `orderId`, `totalAmount` |
| Type parameters | `T` or `T` + PascalCase | `T`, `TKey`, `TValue` |
| Enum members | PascalCase | `OrderStatus.Pending` |

### Async Method Naming

Suffix async methods with `Async`:

```csharp
public Task<Order> GetOrderAsync(int id);
public ValueTask SaveChangesAsync(CancellationToken ct);

Exception: Event handlers and interface implementations where the framework does not use the `Async` suffix (e.g., ASP.NET Core middleware `InvokeAsync` is already named by the framework).
```

### Boolean Naming

Prefix booleans with `is`, `has`, `can`, `should`, or similar:

```csharp
public bool IsActive { get; set; }
public bool HasOrders { get; }
public bool CanDelete(Order order);
```

### Collection Naming

Use plural nouns for collections:

```csharp
public IReadOnlyList<Order> Orders { get; }
public Dictionary<string, int> CountsByName { get; }
```

---

## File Organization

### One Type Per File

Each top-level type (class, record, struct, interface, enum) should be in its own file, named exactly as the type. Nested types stay in the containing type's file.

```
OrderService.cs        -> public class OrderService
IOrderRepository.cs    -> public interface IOrderRepository
OrderStatus.cs         -> public enum OrderStatus
OrderSummary.cs        -> public record OrderSummary
```

### File-Scoped Namespaces

Always use file-scoped namespaces (C# 10+):

```csharp
namespace MyApp.Services;

public class OrderService { }
```

### Using Directives

Place `using` directives at the top of the file, outside the namespace. With `<ImplicitUsings>enable</ImplicitUsings>` (default in modern .NET), common namespaces are already imported.

Order of `using` directives:
1. `System.*` namespaces
2. Third-party namespaces
3. Project namespaces

---

## Code Style

### Braces

Always use braces for control flow, even for single-line bodies:

```csharp
if (order.IsValid)
{
    Process(order);
}
```

### Expression-Bodied Members

Use expression bodies for single-expression members:

```csharp
public string FullName => $"{FirstName} {LastName}";
public override string ToString() => $"Order #{Id}";
```

### `var` Usage

Use `var` when the type is obvious from the right-hand side:

```csharp
var orders = new List<Order>();
var customer = GetCustomerById(id);

IOrderRepository repo = serviceProvider.GetRequiredService<IOrderRepository>();
decimal total = CalculateTotal(items);
```

### Null Handling

Prefer pattern matching over null checks:

```csharp
if (order is not null) { }
if (order is { Status: OrderStatus.Active }) { }

var name = customer?.Name ?? "Unknown";
var orders = customer?.Orders ?? [];
items ??= [];
```

### String Handling

Prefer string interpolation over concatenation or `string.Format`:

```csharp
var message = $"Order {orderId} totals {total:C2}";

var json = $$"""
    {
        "id": {{orderId}},
        "name": "{{name}}"
    }
    """;
```

---

## Access Modifiers

Always specify access modifiers explicitly. Do not rely on defaults:

```csharp
public class OrderService
{
    private readonly IOrderRepository _repo;
    internal void ProcessBatch() { }
}
```

### Modifier Order

```
access (public/private/protected/internal) -> static -> extern -> new ->
virtual/abstract/override/sealed -> readonly -> volatile -> async -> partial
```

```csharp
public static readonly int MaxSize = 100;
protected virtual async Task<Order> LoadAsync() => await repo.GetDefaultAsync();
public sealed override string ToString() => Name;
```

---

## Type Design

### Seal Classes by Default

Seal classes that are not designed for inheritance. This improves performance (devirtualization) and communicates intent:

```csharp
public sealed class OrderService(IOrderRepository repo)
{
}
```

Only leave classes unsealed when you explicitly design them as base classes.

### Prefer Composition Over Inheritance

```csharp
public sealed class OrderProcessor(IValidator validator, INotifier notifier)
{
    public async Task ProcessAsync(Order order)
    {
        await validator.ValidateAsync(order);
        await notifier.NotifyAsync(order);
    }
}
```

### Interface Segregation

Keep interfaces focused. Prefer multiple small interfaces over one large one:

```csharp
public interface IOrderReader
{
    Task<Order?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<Order>> GetAllAsync(CancellationToken ct = default);
}

public interface IOrderWriter
{
    Task<Order> CreateAsync(Order order, CancellationToken ct = default);
    Task UpdateAsync(Order order, CancellationToken ct = default);
}
```

---

## Language Patterns

See [Language Patterns](./reference/language-patterns.md) for detailed guidance on:
- Records for Immutable Data (C# 9+)
- Value Objects as readonly record struct
- Pattern Matching (C# 8-12)
- Nullable Reference Types (C# 8+)
- Composition Over Inheritance

---

## Performance Patterns

See [Performance Patterns](./reference/performance-patterns.md) for detailed guidance on:
- Async/Await Best Practices
- Span<T> and Memory<T> for Zero-Allocation Code

---

## API Design Principles

See [API Design Principles](./reference/api-design.md) for detailed guidance on:
- Accept Abstractions, Return Appropriately Specific
- Method Signatures Best Practices

---

## Error Handling

See [Error Handling](./reference/error-handling.md) for detailed guidance on:
- Result Type Pattern (Railway-Oriented Programming)

---

## Testing Patterns

```csharp
public record OrderBuilder
{
    public OrderId Id { get; init; } = OrderId.New();
    public CustomerId CustomerId { get; init; } = CustomerId.New();
    public Money Total { get; init; } = new Money(100m, "USD");
    public IReadOnlyList<OrderItem> Items { get; init; } = Array.Empty<OrderItem>();

    public Order Build() => new(Id, CustomerId, Total, Items);
}

[Fact]
public void CalculateDiscount_LargeOrder_AppliesCorrectDiscount()
{
    var baseOrder = new OrderBuilder().Build();
    var largeOrder = baseOrder with { Total = new Money(1500m, "USD") };

    var discount = _service.CalculateDiscount(largeOrder);

    discount.Should().Be(new Money(225m, "USD"));
}

[Theory]
[InlineData("ORD-12345", true)]
[InlineData("INVALID", false)]
public void TryParseOrderId_VariousInputs_ReturnsExpectedResult(
    string input, bool expected)
{
    var result = OrderIdParser.TryParse(input.AsSpan(), out var orderId);
    result.Should().Be(expected);
}

[Fact]
public void Money_Add_SameCurrency_ReturnsSum()
{
    var money1 = new Money(100m, "USD");
    var money2 = new Money(50m, "USD");

    var result = money1.Add(money2);

    result.Should().Be(new Money(150m, "USD"));
}

[Fact]
public void Money_Add_DifferentCurrency_ThrowsException()
{
    var usd = new Money(100m, "USD");
    var eur = new Money(50m, "EUR");

    var act = () => usd.Add(eur);
    act.Should().Throw<InvalidOperationException>()
        .WithMessage("*different currencies*");
}
```

---

## CancellationToken Conventions

Accept `CancellationToken` as the last parameter in async methods. Use `default` as the default value for optional tokens:

```csharp
public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
{
    return await _repo.GetByIdAsync(id, ct);
}
```

Always forward the token to downstream async calls. Never ignore a received `CancellationToken`.

---

## XML Documentation

Add XML docs to public API surfaces. Keep them concise:

```csharp
/// <summary>
/// Retrieves an order by its unique identifier.
/// </summary>
/// <param name="id">The order identifier.</param>
/// <param name="ct">Cancellation token.</param>
/// <returns>The order, or <see langword="null"/> if not found.</returns>
public Task<Order?> GetByIdAsync(int id, CancellationToken ct = default);
```

Do not add XML docs to:
- Private or internal members (unless it's a library's `InternalsVisibleTo` API)
- Self-evident members (e.g., `public string Name { get; }`)
- Test methods

---

## Avoid Reflection-Based Metaprogramming

See [Anti-Patterns](./reference/anti-patterns.md#avoid-reflection-based-metaprogramming) for detailed guidance on:
- Why to avoid AutoMapper, Mapster, and similar reflection-based libraries
- Using explicit mapping methods instead
- UnsafeAccessorAttribute for legitimate reflection needs

---

## Anti-Patterns to Avoid

See [Anti-Patterns](./reference/anti-patterns.md#anti-patterns-to-avoid) for detailed guidance on:
- Mutable DTOs
- Classes for value objects
- Deep inheritance hierarchies
- Exposing mutable collections
- Forgetting CancellationToken
- Blocking on async code

---

## Code Organization

```csharp
namespace MyApp.Domain.Orders;

public record Order(
    OrderId Id,
    CustomerId CustomerId,
    Money Total,
    OrderStatus Status,
    IReadOnlyList<OrderItem> Items
)
{
    public bool IsCompleted => Status is OrderStatus.Completed;

    public Result<Order, OrderError> AddItem(OrderItem item)
    {
        if (Status is not OrderStatus.Draft)
            return Result<Order, OrderError>.Failure(
                new OrderError("ORDER_NOT_DRAFT", "Can only add items to draft orders"));

        var newItems = Items.Append(item).ToList();
        var newTotal = new Money(
            Items.Sum(i => i.Total.Amount) + item.Total.Amount,
            Total.Currency);

        return Result<Order, OrderError>.Success(
            this with { Items = newItems, Total = newTotal });
    }
}

public enum OrderStatus
{
    Draft,
    Submitted,
    Processing,
    Completed,
    Cancelled
}

public record OrderItem(
    ProductId ProductId,
    Quantity Quantity,
    Money UnitPrice
)
{
    public Money Total => new(
        UnitPrice.Amount * Quantity.Value,
        UnitPrice.Currency);
}

public readonly record struct OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
}

public readonly record struct OrderError(string Code, string Message);
```

---

## Analyzer Enforcement

Configure these analyzers in `Directory.Build.props` or `.editorconfig` to enforce standards automatically:

```xml
<PropertyGroup>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  <AnalysisLevel>latest-all</AnalysisLevel>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

Key `.editorconfig` rules for C# style:
```ini
[*.cs]
csharp_style_namespace_declarations = file_scoped:warning
csharp_prefer_braces = true:warning
csharp_style_var_for_built_in_types = true:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
dotnet_style_require_accessibility_modifiers = always:warning
csharp_style_prefer_pattern_matching = true:suggestion
```

---

## Best Practices Summary

### DO's 
- Use `record` for DTOs, messages, and domain entities
- Use `readonly record struct` for value objects
- Leverage pattern matching with `switch` expressions
- Enable and respect nullable reference types
- Use async/await for all I/O operations
- Accept `CancellationToken` in all async methods
- Use `Span<T>` and `Memory<T>` for high-performance scenarios
- Accept abstractions (`IEnumerable<T>`, `IReadOnlyList<T>`)
- Return appropriate interfaces or concrete types
- Use `Result<T, TError>` for expected errors
- Use `ConfigureAwait(false)` in library code
- Pool buffers with `ArrayPool<T>` for large allocations
- Prefer composition over inheritance
- Avoid abstract base classes in application code

### DON'Ts 
- Don't use mutable classes when records work
- Don't use classes for value objects (use `readonly record struct`)
- Don't create deep inheritance hierarchies
- Don't ignore nullable reference type warnings
- Don't block on async code (`.Result`, `.Wait()`)
- Don't use `byte[]` when `Span<byte>` suffices
- Don't forget `CancellationToken` parameters
- Don't return mutable collections from APIs
- Don't throw exceptions for expected business errors
- Don't use `string` concatenation in loops
- Don't allocate large arrays repeatedly (use `ArrayPool`)

---

## Knowledge Sources

Conventions in this skill are grounded in publicly available content from:

- **Microsoft Framework Design Guidelines** -- The canonical reference for .NET naming, type design, and API surface conventions. Source: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/
- **C# Language Design Notes (Mads Torgersen et al.)** -- Design rationale behind C# language features that affect coding standards. Key decisions relevant to this skill: file-scoped namespaces (reducing nesting for readability), pattern matching over type checks (expressiveness), `required` members (compile-time initialization safety), and `var` usage guidelines (readability-first). Source: https://github.com/dotnet/csharplang/tree/main/meetings

---

## Additional Resources

- **C# Language Specification**: https://learn.microsoft.com/en-us/dotnet/csharp/
- **Pattern Matching**: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/functional/pattern-matching
- **Span<T> and Memory<T>**: https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/
- **Async Best Practices**: https://learn.microsoft.com/en-us/archive/msdn-magazine/2013/march/async-await-best-practices-in-asynchronous-programming
- **.NET Performance Tips**: https://learn.microsoft.com/en-us/dotnet/framework/performance/
- **C# Coding Conventions**: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions
- **C# Identifier Naming Rules**: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/identifier-names
- **.editorconfig for .NET**: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/code-style-rule-options
