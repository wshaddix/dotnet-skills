# Performance Patterns

## Performance Patterns

### Async/Await Best Practices

**Always use async for I/O-bound operations:**

```csharp
// ✅ GOOD: Async all the way
public async Task<Order> GetOrderAsync(string orderId, CancellationToken cancellationToken)
{
    var order = await _repository.GetAsync(orderId, cancellationToken);
    var customer = await _customerService.GetCustomerAsync(order.CustomerId, cancellationToken);
    return order;
}

// ❌ BAD: Blocking on async code
public Order GetOrder(string orderId)
{
    return _repository.GetAsync(orderId).Result;  // DEADLOCK RISK!
}

// ✅ GOOD: ValueTask for frequently-called, often-synchronous methods
public ValueTask<Order?> GetCachedOrderAsync(string orderId, CancellationToken cancellationToken)
{
    if (_cache.TryGetValue(orderId, out var order))
        return ValueTask.FromResult<Order?>(order);  // Synchronous path, no allocation

    return GetFromDatabaseAsync(orderId, cancellationToken);  // Async path
}

private async ValueTask<Order?> GetFromDatabaseAsync(string orderId, CancellationToken cancellationToken)
{
    var order = await _repository.GetAsync(orderId, cancellationToken);
    if (order is not null)
        _cache[orderId] = order;
    return order;
}

// ✅ GOOD: IAsyncEnumerable for streaming
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

// ✅ GOOD: ConfigureAwait(false) in library code (not application code)
public async Task<string> ProcessDataAsync(string input, CancellationToken cancellationToken)
{
    var data = await FetchDataAsync(cancellationToken).ConfigureAwait(false);
    var result = await TransformDataAsync(data, cancellationToken).ConfigureAwait(false);
    return result;
}
```

**Always accept CancellationToken:**

```csharp
// ✅ GOOD: CancellationToken parameter with default
public async Task<List<Order>> GetOrdersAsync(
    string customerId,
    CancellationToken cancellationToken = default)
{
    var orders = await _repository.GetOrdersByCustomerAsync(customerId, cancellationToken);
    return orders;
}

// Pass cancellation through the call stack
public async Task<OrderSummary> GetOrderSummaryAsync(
    string customerId,
    CancellationToken cancellationToken = default)
{
    var orders = await GetOrdersAsync(customerId, cancellationToken);
    var total = orders.Sum(o => o.Total);
    return new OrderSummary(customerId, orders.Count, total);
}

// Link cancellation tokens when composing operations
public async Task<ProcessResult> ProcessWithTimeoutAsync(
    string data,
    TimeSpan timeout,
    CancellationToken cancellationToken = default)
{
    using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    cts.CancelAfter(timeout);

    return await ProcessAsync(data, cts.Token);
}
```

---

### Span<T> and Memory<T> for Zero-Allocation Code

Use `Span<T>` and `Memory<T>` instead of `byte[]` or `string` for performance-critical code.

```csharp
// ✅ GOOD: Span<T> for synchronous, zero-allocation operations
public int ParseOrderId(ReadOnlySpan<char> input)
{
    // Work with data without allocations
    if (!input.StartsWith("ORD-"))
        throw new FormatException("Invalid order ID format");

    var numberPart = input.Slice(4);
    return int.Parse(numberPart);
}

// stackalloc with Span<T>
public void FormatMessage()
{
    Span<char> buffer = stackalloc char[256];
    var written = FormatInto(buffer);
    var message = new string(buffer.Slice(0, written));
}

// SkipLocalsInit with stackalloc - skips zero-initialization for performance
// By default, .NET zero-initializes all locals (.locals init flag). This can have
// measurable overhead with stackalloc. Use [SkipLocalsInit] when:
//   - You write to the buffer before reading (like FormatInto below)
//   - Profiling shows zero-init as a bottleneck
// ⚠️ WARNING: Reading before writing returns garbage data (see docs example)
// Requires: <AllowUnsafeBlocks>true</AllowUnsafeBlocks> in .csproj
// See: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/attributes/general#skiplocalsinit-attribute
using System.Runtime.CompilerServices;
[SkipLocalsInit]
public void FormatMessage()
{
    Span<char> buffer = stackalloc char[256];
    var written = FormatInto(buffer);
    var message = new string(buffer.Slice(0, written));
}

// ✅ GOOD: Memory<T> for async operations (Span can't cross await)
public async Task<int> ReadDataAsync(
    Memory<byte> buffer,
    CancellationToken cancellationToken)
{
    return await _stream.ReadAsync(buffer, cancellationToken);
}

// ✅ GOOD: String manipulation with Span to avoid allocations
public bool TryParseKeyValue(ReadOnlySpan<char> line, out string key, out string value)
{
    key = string.Empty;
    value = string.Empty;

    int colonIndex = line.IndexOf(':');
    if (colonIndex == -1)
        return false;

    // Only allocate strings once we know the format is valid
    key = new string(line.Slice(0, colonIndex).Trim());
    value = new string(line.Slice(colonIndex + 1).Trim());
    return true;
}

// ✅ GOOD: ArrayPool for temporary large buffers
public async Task ProcessLargeFileAsync(
    Stream stream,
    CancellationToken cancellationToken)
{
    var buffer = ArrayPool<byte>.Shared.Rent(8192);
    try
    {
        int bytesRead;
        while ((bytesRead = await stream.ReadAsync(buffer.AsMemory(), cancellationToken)) > 0)
        {
            ProcessChunk(buffer.AsSpan(0, bytesRead));
        }
    }
    finally
    {
        ArrayPool<byte>.Shared.Return(buffer);
    }
}

// Hybrid buffer pattern for transient UTF-8 work. See caveats of SkipLocalsInit in the corresponding section.

[SkipLocalsInit]
static short GenerateHashCode(string? key)
{
    if (key is null) return 0;

    const int StackLimit = 256;

    var enc = Encoding.UTF8;
    var max = enc.GetMaxByteCount(key.Length);

    byte[]? rented = null;
    Span<byte> buf = max <= StackLimit
        ? stackalloc byte[StackLimit]
        : (rented = ArrayPool<byte>.Shared.Rent(max));

    try
    {
        var written = enc.GetBytes(key.AsSpan(), buf);
        ComputeHash(buf[..written], out var h1, out var h2);
        return unchecked((short)(h1 ^ h2));
    }
    finally
    {
        if (rented is not null) ArrayPool<byte>.Shared.Return(rented);
    }
}

// ✅ GOOD: Span-based parsing without substring allocations
public static (string Protocol, string Host, int Port) ParseUrl(ReadOnlySpan<char> url)
{
    var protocolEnd = url.IndexOf("://");
    var protocol = new string(url.Slice(0, protocolEnd));

    var afterProtocol = url.Slice(protocolEnd + 3);
    var portStart = afterProtocol.IndexOf(':');

    var host = new string(afterProtocol.Slice(0, portStart));
    var portSpan = afterProtocol.Slice(portStart + 1);
    var port = int.Parse(portSpan);

    return (protocol, host, port);
}

// ✅ GOOD: Writing data to Span
public bool TryFormatOrderId(int orderId, Span<char> destination, out int charsWritten)
{
    const string prefix = "ORD-";

    if (destination.Length < prefix.Length + 10)
    {
        charsWritten = 0;
        return false;
    }

    prefix.AsSpan().CopyTo(destination);
    var numberWritten = orderId.TryFormat(
        destination.Slice(prefix.Length),
        out var numberChars);

    charsWritten = prefix.Length + numberChars;
    return numberWritten;
}
```

**When to use what:**

| Type | Use Case |
|------|----------|
| `Span<T>` | Synchronous operations, stack-allocated buffers, slicing without allocation |
| `ReadOnlySpan<T>` | Read-only views, method parameters for data you won't modify |
| `Memory<T>` | Async operations (Span can't cross await boundaries) |
| `ReadOnlyMemory<T>` | Read-only async operations |
| `byte[]` | When you need to store data long-term or pass to APIs requiring arrays |
| `ArrayPool<T>` | Large temporary buffers (>1KB) to avoid GC pressure |

---
