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
// Use record for test data builders
public record OrderBuilder
{
    public OrderId Id { get; init; } = OrderId.New();
    public CustomerId CustomerId { get; init; } = CustomerId.New();
    public Money Total { get; init; } = new Money(100m, "USD");
    public IReadOnlyList<OrderItem> Items { get; init; } = Array.Empty<OrderItem>();

    public Order Build() => new(Id, CustomerId, Total, Items);
}

// Use 'with' expression for test variations
[Fact]
public void CalculateDiscount_LargeOrder_AppliesCorrectDiscount()
{
    // Arrange
    var baseOrder = new OrderBuilder().Build();
    var largeOrder = baseOrder with
    {
        Total = new Money(1500m, "USD")
    };

    // Act
    var discount = _service.CalculateDiscount(largeOrder);

    // Assert
    discount.Should().Be(new Money(225m, "USD")); // 15% of 1500
}

// Span-based testing
[Theory]
[InlineData("ORD-12345", true)]
[InlineData("INVALID", false)]
public void TryParseOrderId_VariousInputs_ReturnsExpectedResult(
    string input,
    bool expected)
{
    // Act
    var result = OrderIdParser.TryParse(input.AsSpan(), out var orderId);

    // Assert
    result.Should().Be(expected);
}

// Testing with value objects
[Fact]
public void Money_Add_SameCurrency_ReturnsSum()
{
    // Arrange
    var money1 = new Money(100m, "USD");
    var money2 = new Money(50m, "USD");

    // Act
    var result = money1.Add(money2);

    // Assert
    result.Should().Be(new Money(150m, "USD"));
}

[Fact]
public void Money_Add_DifferentCurrency_ThrowsException()
{
    // Arrange
    var usd = new Money(100m, "USD");
    var eur = new Money(50m, "EUR");

    // Act & Assert
    var act = () => usd.Add(eur);
    act.Should().Throw<InvalidOperationException>()
        .WithMessage("*different currencies*");
}
```

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
// File: Domain/Orders/Order.cs

namespace MyApp.Domain.Orders;

// 1. Primary domain type
public record Order(
    OrderId Id,
    CustomerId CustomerId,
    Money Total,
    OrderStatus Status,
    IReadOnlyList<OrderItem> Items
)
{
    // Computed properties
    public bool IsCompleted => Status is OrderStatus.Completed;

    // Domain methods returning Result for expected errors
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

// 2. Enums for state
public enum OrderStatus
{
    Draft,
    Submitted,
    Processing,
    Completed,
    Cancelled
}

// 3. Related types
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

// 4. Value objects
public readonly record struct OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
}

// 5. Errors
public readonly record struct OrderError(string Code, string Message);
```

---

## Best Practices Summary

### DO's ✅
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

### DON'Ts ❌
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

## Additional Resources

- **C# Language Specification**: https://learn.microsoft.com/en-us/dotnet/csharp/
- **Pattern Matching**: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/functional/pattern-matching
- **Span<T> and Memory<T>**: https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/
- **Async Best Practices**: https://learn.microsoft.com/en-us/archive/msdn-magazine/2013/march/async-await-best-practices-in-asynchronous-programming
- **.NET Performance Tips**: https://learn.microsoft.com/en-us/dotnet/framework/performance/
