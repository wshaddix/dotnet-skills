---
name: type-design-performance
description: Design .NET types for performance. Covers struct vs class decision matrix, sealed by default, readonly structs, ref struct and Span/Memory selection, FrozenDictionary, ValueTask, and collection return types. Use when designing new types and APIs, reviewing code for performance issues, choosing between class, struct, and record, or working with collections and enumerables.
---

# Type Design for Performance

## When to Use This Skill

Use this skill when:
- Designing new types and APIs
- Reviewing code for performance issues
- Choosing between class, struct, and record
- Working with collections and enumerables

## Core Principles

1. **Seal your types** - Unless explicitly designed for inheritance
2. **Prefer readonly structs** - For small, immutable value types
3. **Prefer static pure functions** - Better performance and testability
4. **Defer enumeration** - Don't materialize until you need to
5. **Return immutable collections** - From API boundaries

---

## Struct vs Class Decision Matrix

Choosing between `struct` and `class` at design time has cascading effects on allocation, GC pressure, and API shape.

### Decision Criteria

| Criterion | Favors `struct` | Favors `class` |
|-----------|----------------|----------------|
| Size | Small (<= 16 bytes ideal, <= 64 bytes acceptable) | Large or variable size |
| Lifetime | Short-lived, method-scoped | Long-lived, shared across scopes |
| Identity | Value equality (two instances with same data are equal) | Reference identity matters |
| Mutability | Immutable (`readonly struct`) | Mutable or complex state transitions |
| Inheritance | Not needed | Requires polymorphism or base class |
| Nullable semantics | `default` is a valid zero state | Needs explicit null to signal absence |
| Collection usage | Stored in arrays/spans (contiguous memory) | Stored via references (indirection) |

### Size Guidelines

```
<= 16 bytes:  Ideal struct -- fits in two registers, passed efficiently
17-64 bytes:  Acceptable struct -- measure copy cost vs allocation cost
> 64 bytes:   Prefer class -- copying cost outweighs allocation avoidance
```

### Common Types and Their Correct Design

| Type | Correct Choice | Why |
|------|---------------|-----|
| Point2D (8 bytes: two floats) | `readonly struct` | Small, immutable, value semantics |
| Money (16 bytes: decimal + currency) | `readonly struct` | Small, immutable, value equality |
| DateRange (16 bytes: two DateOnly) | `readonly struct` | Small, immutable, value semantics |
| Matrix4x4 (64 bytes: 16 floats) | `struct` (with `in` parameters) | Performance-critical math |
| CustomerDto (variable: strings, lists) | `class` or `record` | Contains references, variable size |
| HttpRequest context | `class` | Long-lived, shared across middleware |

---

## Sealed by Default

### Why Seal Library Types

For library types (code consumed by other assemblies), seal classes by default:

1. **JIT devirtualization** -- sealed classes enable the JIT to replace virtual calls with direct calls, enabling inlining
2. **Simpler contracts** -- unsealed classes imply a promise to support inheritance
3. **Fewer breaking changes** -- sealing a class later is a binary-breaking change

```csharp
// GOOD -- sealed by default for library types
public sealed class WidgetService
{
    public Widget GetWidget(int id) => new(id, "Default");
}

// Only unseal when inheritance is an intentional design decision
public abstract class WidgetValidatorBase
{
    public abstract bool Validate(Widget widget);
    protected virtual void OnValidationComplete(Widget widget) { }
}
```

### When NOT to Seal

| Scenario | Reason |
|----------|--------|
| Abstract base classes | Inheritance is the purpose |
| Framework extensibility points | Consumers need to subclass |
| Test doubles in non-mockable designs | Mocking frameworks need to subclass |
| Application-internal classes | Sealing adds no value |

---

## Readonly Structs

Mark structs `readonly` when all fields are immutable. This eliminates defensive copies the JIT creates when accessing structs through `in` parameters or `readonly` fields.

### The Defensive Copy Problem

```csharp
// NON-readonly struct -- JIT must defensively copy on every method call
public struct MutablePoint
{
    public double X;
    public double Y;
    public double Length() => Math.Sqrt(X * X + Y * Y);
}

public double GetLength(in MutablePoint point)
{
    return point.Length(); // Hidden copy here!
}
```

```csharp
// GOOD -- readonly struct: JIT knows no mutation is possible
public readonly struct ImmutablePoint
{
    public double X { get; }
    public double Y { get; }

    public ImmutablePoint(double x, double y) => (X, Y) = (x, y);

    public double Length() => Math.Sqrt(X * X + Y * Y);
}

public double GetLength(in ImmutablePoint point)
{
    return point.Length(); // No copy, direct call
}
```

### Readonly Struct Checklist

- All fields are `readonly` or `{ get; }` / `{ get; init; }` properties
- No methods mutate state
- Constructor initializes all fields
- Consider `IEquatable<T>` for value comparison without boxing

---

## Record Types for Data Transfer

### record class vs record struct

| Characteristic | `record class` | `record struct` |
|---------------|---------------|-----------------|
| Allocation | Heap | Stack (or inline in arrays) |
| Equality | Reference type with value equality | Value type with value equality |
| `with` expression | Creates new heap object | Creates new stack copy |
| Nullable | `null` represents absence | `default` represents empty state |
| Size | Reference (8 bytes on x64) + heap | Full size on stack |

```csharp
// record class -- heap allocated, good for DTOs
public record CustomerDto(string Name, string Email, DateOnly JoinDate);

// readonly record struct -- stack allocated, good for small value objects
public readonly record struct Money(decimal Amount, string Currency);
```

---

## Prefer Static Pure Functions

Static methods with no side effects are faster and more testable.

```csharp
// DO: Static pure function
public static class OrderCalculator
{
    public static Money CalculateTotal(IReadOnlyList<OrderItem> items)
    {
        var total = items.Sum(i => i.Price * i.Quantity);
        return new Money(total, "USD");
    }
}

// Usage - predictable, testable
var total = OrderCalculator.CalculateTotal(items);
```

**Benefits:**
- No vtable lookup (faster)
- No hidden state
- Easier to test (pure input → output)
- Thread-safe by design
- Forces explicit dependencies

---

## Defer Enumeration

Don't materialize enumerables until necessary. Avoid excessive LINQ chains.

```csharp
// BAD: Premature materialization
public IReadOnlyList<Order> GetActiveOrders()
{
    return _orders
        .Where(o => o.IsActive)
        .ToList()  // Materialized!
        .OrderBy(o => o.CreatedAt)  // Another iteration
        .ToList();  // Materialized again!
}

// GOOD: Defer until the end
public IReadOnlyList<Order> GetActiveOrders()
{
    return _orders
        .Where(o => o.IsActive)
        .OrderBy(o => o.CreatedAt)
        .ToList();  // Single materialization
}

// GOOD: Return IEnumerable if caller might not need all items
public IEnumerable<Order> GetActiveOrders()
{
    return _orders
        .Where(o => o.IsActive)
        .OrderBy(o => o.CreatedAt);
}
```

### Async Enumeration

```csharp
// GOOD: Use IAsyncEnumerable for streaming
public async IAsyncEnumerable<OrderResult> ProcessOrdersAsync(
    IEnumerable<Order> orders,
    [EnumeratorCancellation] CancellationToken ct = default)
{
    foreach (var order in orders)
    {
        ct.ThrowIfCancellationRequested();
        yield return await ProcessOrderAsync(order, ct);
    }
}

// GOOD: Batch processing for parallelism
var results = await Task.WhenAll(
    orders.Select(o => ProcessOrderAsync(o)));
```

---

## ValueTask vs Task

Use `ValueTask` for hot paths that often complete synchronously. For real I/O, just use `Task`.

```csharp
// DO: ValueTask for cached/synchronous paths
public ValueTask<User?> GetUserAsync(UserId id)
{
    if (_cache.TryGetValue(id, out var user))
    {
        return ValueTask.FromResult<User?>(user);  // No allocation
    }

    return new ValueTask<User?>(FetchUserAsync(id));
}

// DO: Task for real I/O (simpler, no footguns)
public Task<Order> CreateOrderAsync(CreateOrderCommand cmd)
{
    return _repository.CreateAsync(cmd);
}
```

**ValueTask rules:**
- Never await a ValueTask more than once
- Never use `.Result` or `.GetAwaiter().GetResult()` before completion
- If in doubt, use Task

---

## ref struct and Span/Memory Selection

### ref struct Constraints

`ref struct` types are stack-only: they cannot be boxed, stored in fields of non-ref-struct types, or used in async methods.

### Span<T> vs Memory<T> Decision

| Criterion | Use `Span<T>` | Use `Memory<T>` |
|-----------|--------------|-----------------|
| Synchronous method | Yes | Yes (but Span is lower overhead) |
| Async method | No (ref struct) | Yes |
| Store in field/collection | No (ref struct) | Yes |
| Pass to callback/delegate | No | Yes |
| Slice without allocation | Yes | Yes |
| Wrap stackalloc buffer | Yes | No |

### Selection Flowchart

```
Will the buffer be used in an async method or stored in a field?
  YES -> Use Memory<T> (convert to Span<T> with .Span for synchronous processing)
  NO  -> Do you need to wrap a stackalloc buffer?
           YES -> Use Span<T>
           NO  -> Prefer Span<T> for lowest overhead
```

### Practical Pattern

```csharp
// Public API uses Memory<T> for maximum flexibility
public async Task<int> ProcessAsync(ReadOnlyMemory<byte> data,
    CancellationToken ct = default)
{
    await _stream.WriteAsync(data, ct);
    return CountNonZero(data.Span);
}

// Internal hot-path method uses Span<T> for zero overhead
private static int CountNonZero(ReadOnlySpan<byte> data)
{
    var count = 0;
    foreach (var b in data)
    {
        if (b != 0) count++;
    }
    return count;
}
```

### Common Span Patterns

```csharp
// Slice without allocation
ReadOnlySpan<char> span = "Hello, World!".AsSpan();
var hello = span[..5];  // No allocation

// Stack allocation for small buffers
Span<byte> buffer = stackalloc byte[256];

// Use ArrayPool for larger buffers
var buffer = ArrayPool<byte>.Shared.Rent(4096);
try
{
    // Use buffer...
}
finally
{
    ArrayPool<byte>.Shared.Return(buffer);
}
```

---

## Collection Type Selection

### Decision Matrix

| Scenario | Recommended Type | Rationale |
|----------|-----------------|-----------|
| Build once, read many | `FrozenDictionary<K,V>` / `FrozenSet<T>` | Optimized read layout (.NET 8+) |
| Build once, read many (pre-.NET 8) | `ImmutableDictionary<K,V>` | Thread-safe, immutable |
| Concurrent read/write | `ConcurrentDictionary<K,V>` | Thread-safe without external locking |
| Frequent modifications | `Dictionary<K,V>` | Lowest per-operation overhead |
| Ordered data | `SortedDictionary<K,V>` | O(log n) lookup with sorted enumeration |
| Return from public API | `IReadOnlyList<T>` / `IReadOnlyDictionary<K,V>` | Immutable interface |
| Stack-allocated small collection | `Span<T>` with stackalloc | Zero GC pressure |

### FrozenDictionary (.NET 8+)

`FrozenDictionary<K,V>` optimizes the internal layout at creation time for maximum read performance:

```csharp
using System.Collections.Frozen;

private static readonly FrozenDictionary<string, int> StatusCodes =
    new Dictionary<string, int>
    {
        ["OK"] = 200,
        ["NotFound"] = 404,
        ["InternalServerError"] = 500
    }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

public int GetStatusCode(string name) =>
    StatusCodes.TryGetValue(name, out var code) ? code : -1;
```

**When to use FrozenDictionary:**
- Configuration lookup tables populated at startup
- Static mappings (enum-to-string, error codes, feature flags)
- Any dictionary populated once and read many times

**When NOT to use:**
- Data that changes at runtime
- Small lookups (< 10 items) where optimization overhead is not recouped

### Collection Return Types

```csharp
// DO: Return immutable collection
public IReadOnlyList<Order> GetOrders()
{
    return _orders.ToList();
}

// DO: Use frozen collections for static data
private static readonly FrozenDictionary<string, Handler> _handlers =
    new Dictionary<string, Handler>
    {
        ["create"] = new CreateHandler(),
        ["update"] = new UpdateHandler(),
    }.ToFrozenDictionary();

// DON'T: Return mutable collection
public List<Order> GetOrders()
{
    return _orders;  // Caller can modify!
}
```

---

## Quick Reference

| Pattern | Benefit |
|---------|---------|
| `sealed class` | Devirtualization, clear API |
| `readonly record struct` | No defensive copies, value semantics |
| Static pure functions | No vtable, testable, thread-safe |
| Defer `.ToList()` | Single materialization |
| `ValueTask` for hot paths | Avoid Task allocation |
| `Span<T>` for bytes | Stack allocation, no copying |
| `IReadOnlyList<T>` return | Immutable API contract |
| `FrozenDictionary` | Fastest lookup for static data |

---

## Anti-Patterns

```csharp
// DON'T: Unsealed class without reason
public class OrderService { }  // Seal it!

// DON'T: Mutable struct
public struct Point { public int X; public int Y; }  // Make readonly

// DON'T: Instance method that could be static
public int Add(int a, int b) => a + b;  // Make static

// DON'T: Multiple ToList() calls
items.Where(...).ToList().OrderBy(...).ToList();  // One ToList at end

// DON'T: Return List<T> from public API
public List<Order> GetOrders();  // Return IReadOnlyList<T>

// DON'T: ValueTask for always-async operations
public ValueTask<Order> CreateOrderAsync();  // Just use Task

// DON'T: Use `Span<T>` in async methods
public async Task ProcessAsync(Span<byte> data);  // Use Memory<T>

// DON'T: Use `FrozenDictionary` for mutable data
// It has no add/remove APIs
```

---

## Agent Gotchas

1. **Do not default to `class` for every type** -- evaluate the struct vs class decision matrix.
2. **Do not create non-readonly structs** -- mutable structs cause subtle bugs.
3. **Do not use `Span<T>` in async methods** -- use `Memory<T>` for async code.
4. **Do not use `FrozenDictionary` for mutable data** -- it has no add/remove APIs.
5. **Do not seal abstract classes or classes designed as extension points**.
6. **Do not make large structs (> 64 bytes) without measuring** -- benchmark copy cost.
7. **Do not use `Dictionary<K,V>` for static lookup tables in hot paths** -- use `FrozenDictionary`.
8. **Do not forget `in` parameter for large readonly structs** -- without `in`, the struct is copied.

---

## Resources

- **Performance Best Practices**: https://learn.microsoft.com/en-us/dotnet/standard/performance/
- **Span<T> Guidance**: https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/
- **Frozen Collections**: https://learn.microsoft.com/en-us/dotnet/api/system.collections.frozen
- **Framework Design Guidelines: Type Design**: https://learn.microsoft.com/dotnet/standard/design-guidelines/type
- **Choosing between class and struct**: https://learn.microsoft.com/dotnet/standard/design-guidelines/choosing-between-class-and-struct
- **ref struct types**: https://learn.microsoft.com/dotnet/csharp/language-reference/builtin-types/ref-struct
- **Records (C# reference)**: https://learn.microsoft.com/dotnet/csharp/language-reference/builtin-types/record
