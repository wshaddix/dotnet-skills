# API Design Principles

## API Design Principles

### Accept Abstractions, Return Appropriately Specific

**For Parameters (Accept):**

```csharp
// ✅ GOOD: Accept IEnumerable<T> if you only iterate once
public decimal CalculateTotal(IEnumerable<OrderItem> items)
{
    return items.Sum(item => item.Price * item.Quantity);
}

// ✅ GOOD: Accept IReadOnlyCollection<T> if you need Count
public bool HasMinimumItems(IReadOnlyCollection<OrderItem> items, int minimum)
{
    return items.Count >= minimum;
}

// ✅ GOOD: Accept IReadOnlyList<T> if you need indexing
public OrderItem GetMiddleItem(IReadOnlyList<OrderItem> items)
{
    if (items.Count == 0)
        throw new ArgumentException("List cannot be empty");

    return items[items.Count / 2];  // Indexed access
}

// ✅ GOOD: Accept ReadOnlySpan<T> for high-performance, zero-allocation APIs
public int Sum(ReadOnlySpan<int> numbers)
{
    int total = 0;
    foreach (var num in numbers)
        total += num;
    return total;
}

// ✅ GOOD: Accept IAsyncEnumerable<T> for async streaming
public async Task<int> CountItemsAsync(
    IAsyncEnumerable<Order> orders,
    CancellationToken cancellationToken)
{
    int count = 0;
    await foreach (var order in orders.WithCancellation(cancellationToken))
        count++;
    return count;
}
```

**For Return Types:**

```csharp
// ✅ GOOD: Return IEnumerable<T> for lazy/deferred execution
public IEnumerable<Order> GetOrdersLazy(string customerId)
{
    foreach (var order in _repository.Query())
    {
        if (order.CustomerId == customerId)
            yield return order;  // Lazy evaluation
    }
}

// ✅ GOOD: Return IReadOnlyList<T> for materialized, immutable collections
public IReadOnlyList<Order> GetOrders(string customerId)
{
    return _repository
        .Query()
        .Where(o => o.CustomerId == customerId)
        .ToList();  // Materialized
}

// ✅ GOOD: Return concrete types when callers need mutation
public List<Order> GetMutableOrders(string customerId)
{
    // Explicitly allow mutation by returning List<T>
    return _repository
        .Query()
        .Where(o => o.CustomerId == customerId)
        .ToList();
}

// ✅ GOOD: Return IAsyncEnumerable<T> for async streaming
public async IAsyncEnumerable<Order> StreamOrdersAsync(
    string customerId,
    [EnumeratorCancellation] CancellationToken cancellationToken = default)
{
    await foreach (var order in _repository.StreamAllAsync(cancellationToken))
    {
        if (order.CustomerId == customerId)
            yield return order;
    }
}

// ✅ GOOD: Return arrays for interop or when caller expects array
public byte[] SerializeOrder(Order order)
{
    // Binary serialization - byte[] is appropriate here
    return MessagePackSerializer.Serialize(order);
}
```

**Summary Table:**

| Scenario | Accept | Return |
|----------|--------|--------|
| Only iterate once | `IEnumerable<T>` | `IEnumerable<T>` (if lazy) |
| Need count | `IReadOnlyCollection<T>` | `IReadOnlyCollection<T>` |
| Need indexing | `IReadOnlyList<T>` | `IReadOnlyList<T>` |
| High-performance, sync | `ReadOnlySpan<T>` | `Span<T>` (rarely) |
| Async streaming | `IAsyncEnumerable<T>` | `IAsyncEnumerable<T>` |
| Caller needs mutation | - | `List<T>`, `T[]` |

---

### Method Signatures Best Practices

```csharp
// ✅ GOOD: Complete async method signature
public async Task<Result<Order, OrderError>> CreateOrderAsync(
    CreateOrderRequest request,
    CancellationToken cancellationToken = default)
{
    // Implementation
}

// ✅ GOOD: Optional parameters at the end
public async Task<List<Order>> GetOrdersAsync(
    string customerId,
    DateTime? startDate = null,
    DateTime? endDate = null,
    CancellationToken cancellationToken = default)
{
    // Implementation
}

// ✅ GOOD: Use record for multiple related parameters
public record SearchOrdersRequest(
    string? CustomerId,
    DateTime? StartDate,
    DateTime? EndDate,
    OrderStatus? Status,
    int PageSize = 20,
    int PageNumber = 1
);

public async Task<PagedResult<Order>> SearchOrdersAsync(
    SearchOrdersRequest request,
    CancellationToken cancellationToken = default)
{
    // Implementation
}

// ✅ GOOD: Primary constructors (C# 12+) for simple classes
public sealed class OrderService(IOrderRepository repository, ILogger<OrderService> logger)
{
    public async Task<Order> GetOrderAsync(OrderId orderId, CancellationToken cancellationToken)
    {
        logger.LogInformation("Fetching order {OrderId}", orderId);
        return await repository.GetAsync(orderId, cancellationToken);
    }
}

// ✅ GOOD: Options pattern for complex configuration
public sealed class EmailServiceOptions
{
    public required string SmtpHost { get; init; }
    public int SmtpPort { get; init; } = 587;
    public bool UseSsl { get; init; } = true;
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(30);
}

public sealed class EmailService(IOptions<EmailServiceOptions> options)
{
    private readonly EmailServiceOptions _options = options.Value;
}
```

---
