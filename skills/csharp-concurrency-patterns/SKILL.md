---
name: csharp-concurrency-patterns
description: Choosing the right concurrency abstraction in .NET - from async/await for I/O to Channels for producer/consumer to Akka.NET for stateful entity management. Covers both high-level abstractions and low-level synchronization primitives. Use when deciding how to handle concurrent operations in .NET, evaluating whether to use async/await, Channels, or Akka.NET, or managing state across multiple concurrent entities.
---

# .NET Concurrency: Choosing the Right Tool

## When to Use This Skill

Use this skill when:
- Deciding how to handle concurrent operations in .NET
- Evaluating whether to use async/await, Channels, Akka.NET, or other abstractions
- Tempted to use locks, semaphores, or other synchronization primitives
- Need to process streams of data with backpressure, batching, or debouncing
- Managing state across multiple concurrent entities

## The Philosophy

**Start simple, escalate only when needed.**

Most concurrency problems can be solved with `async/await`. Only reach for more sophisticated tools when you have a specific need that async/await can't address cleanly.

**Try to avoid shared mutable state.** The best way to handle concurrency is to design it away. Immutable data, message passing, and isolated state (like actors) eliminate entire categories of bugs.

**Locks should be the exception, not the rule.** When you can't avoid shared mutable state, using a lock occasionally isn't the end of the world. But if you find yourself reaching for `lock`, `SemaphoreSlim`, or other synchronization primitives regularly, step back and reconsider your design.

When you truly need shared mutable state:
1. **First choice:** Redesign to avoid it (immutability, message passing, actor isolation)
2. **Second choice:** Use `System.Collections.Concurrent` (ConcurrentDictionary, ConcurrentQueue, etc.)
3. **Third choice:** Use `Channel<T>` to serialize access through message passing
4. **Last resort:** Use `lock` for simple, short-lived critical sections

---

## Decision Tree

```
What are you trying to do?
│
├─► Wait for I/O (HTTP, database, file)?
│   └─► Use async/await
│
├─► Process a collection in parallel (CPU-bound)?
│   └─► Use Parallel.ForEachAsync
│
├─► Producer/consumer pattern (work queue)?
│   └─► Use System.Threading.Channels
│
├─► UI event handling (debounce, throttle, combine)?
│   └─► Use Reactive Extensions (Rx)
│
├─► Server-side stream processing (backpressure, batching)?
│   └─► Use Akka.NET Streams
│
├─► State machines with complex transitions?
│   └─► Use Akka.NET Actors (Become pattern)
│
├─► Manage state for many independent entities?
│   └─► Use Akka.NET Actors (entity-per-actor)
│
├─► Coordinate multiple async operations?
│   └─► Use Task.WhenAll / Task.WhenAny
│
├─► Need to protect shared mutable state with synchronization?
│   └─► Is the shared state a single scalar (int, long, reference)?
│       YES -> Use Interlocked (lock-free, lowest overhead)
│
│       Is the shared state a key-value lookup or queue?
│       YES -> Use ConcurrentDictionary / ConcurrentQueue (thread-safe by design)
│
│       Does the critical section contain `await`?
│       YES -> Use SemaphoreSlim (async-compatible via WaitAsync)
│       NO  -> Does the critical section need many readers, few writers?
│                YES -> Use ReaderWriterLockSlim (only if profiling shows lock contention)
│                NO  -> Use lock (simplest, lowest cognitive overhead)
│
│       Is the critical section extremely short (< 100 ns) with high contention?
│       YES -> Consider SpinLock (advanced, measure first)
│
└─► None of the above fits?
    └─► Ask yourself: "Do I really need shared mutable state?"
        ├─► Yes -> Consider redesigning to avoid it
        └─► Truly unavoidable -> Use Channels or Actors to serialize access
```

---

## Level 1: async/await (Default Choice)

**Use for:** I/O-bound operations, non-blocking waits, most everyday concurrency.

```csharp
public async Task<Order> GetOrderAsync(string orderId, CancellationToken ct)
{
    var order = await _database.GetAsync(orderId, ct);
    var customer = await _customerService.GetAsync(order.CustomerId, ct);
    return order with { Customer = customer };
}

public async Task<Dashboard> LoadDashboardAsync(string userId, CancellationToken ct)
{
    var ordersTask = _orderService.GetRecentOrdersAsync(userId, ct);
    var notificationsTask = _notificationService.GetUnreadAsync(userId, ct);
    var statsTask = _statsService.GetUserStatsAsync(userId, ct);

    await Task.WhenAll(ordersTask, notificationsTask, statsTask);

    return new Dashboard(
        Orders: await ordersTask,
        Notifications: await notificationsTask,
        Stats: await statsTask);
}
```

**Key principles:**
- Always accept `CancellationToken`
- Use `ConfigureAwait(false)` in library code
- Don't block on async code (no `.Result` or `.Wait()`)

---

## Level 2: Parallel.ForEachAsync (CPU-Bound Parallelism)

**Use for:** Processing collections in parallel when work is CPU-bound or you need controlled concurrency.

```csharp
public async Task ProcessOrdersAsync(
    IEnumerable<Order> orders,
    CancellationToken ct)
{
    await Parallel.ForEachAsync(
        orders,
        new ParallelOptions
        {
            MaxDegreeOfParallelism = Environment.ProcessorCount,
            CancellationToken = ct
        },
        async (order, token) =>
        {
            await ProcessOrderAsync(order, token);
        });
}

public async Task<IReadOnlyList<ProcessedImage>> ProcessImagesAsync(
    IEnumerable<string> imagePaths,
    CancellationToken ct)
{
    var results = new ConcurrentBag<ProcessedImage>();

    await Parallel.ForEachAsync(
        imagePaths,
        new ParallelOptions { MaxDegreeOfParallelism = 4, CancellationToken = ct },
        async (path, token) =>
        {
            var image = await File.ReadAllBytesAsync(path, token);
            var processed = ProcessImage(image);
            results.Add(processed);
        });

    return results.ToList();
}
```

**When NOT to use:**
- Pure I/O operations (async/await is sufficient)
- When order matters (Parallel doesn't preserve order)
- When you need backpressure or flow control

---

## Level 3: System.Threading.Channels (Producer/Consumer)

**Use for:** Work queues, producer/consumer patterns, decoupling producers from consumers, simple stream-like processing.

```csharp
public class OrderProcessor
{
    private readonly Channel<Order> _channel;

    public OrderProcessor()
    {
        _channel = Channel.CreateBounded<Order>(new BoundedChannelOptions(100)
        {
            FullMode = BoundedChannelFullMode.Wait
        });
    }

    public async Task EnqueueOrderAsync(Order order, CancellationToken ct)
    {
        await _channel.Writer.WriteAsync(order, ct);
    }

    public async Task ProcessOrdersAsync(CancellationToken ct)
    {
        await foreach (var order in _channel.Reader.ReadAllAsync(ct))
        {
            await ProcessOrderAsync(order, ct);
        }
    }

    public void Complete() => _channel.Writer.Complete();
}
```

```csharp
public class WorkerPool
{
    private readonly Channel<WorkItem> _channel;
    private readonly List<Task> _workers = new();

    public WorkerPool(int workerCount)
    {
        _channel = Channel.CreateUnbounded<WorkItem>();

        for (int i = 0; i < workerCount; i++)
        {
            _workers.Add(Task.Run(() => ConsumeAsync()));
        }
    }

    private async Task ConsumeAsync()
    {
        await foreach (var item in _channel.Reader.ReadAllAsync())
        {
            await ProcessAsync(item);
        }
    }

    public ValueTask EnqueueAsync(WorkItem item)
        => _channel.Writer.WriteAsync(item);
}
```

**Channels are good for:**
- Decoupling producer speed from consumer speed
- Buffering work with backpressure
- Simple fan-out to multiple workers
- Background processing queues

**Channels are NOT good for:**
- Complex stream operations (batching, windowing, merging)
- Stateful processing per entity
- When you need sophisticated error handling/supervision

---

## Level 4: Akka.NET Streams (Complex Stream Processing)

**Use for:** Backpressure, batching, debouncing, throttling, merging streams, complex transformations.

```csharp
using Akka.Streams;
using Akka.Streams.Dsl;

public Source<IReadOnlyList<Event>, NotUsed> BatchEvents(
    Source<Event, NotUsed> events)
{
    return events
        .GroupedWithin(100, TimeSpan.FromSeconds(1))
        .Select(batch => batch.ToList() as IReadOnlyList<Event>);
}

public Source<Request, NotUsed> ThrottleRequests(
    Source<Request, NotUsed> requests)
{
    return requests
        .Throttle(10, TimeSpan.FromSeconds(1), 5, ThrottleMode.Shaping);
}

public Source<ProcessedItem, NotUsed> ProcessWithParallelism(
    Source<Item, NotUsed> items)
{
    return items
        .SelectAsync(4, async item => await ProcessAsync(item));
}

public IRunnableGraph<Task<Done>> CreatePipeline(
    Source<RawEvent, NotUsed> events,
    Sink<ProcessedEvent, Task<Done>> sink)
{
    return events
        .Where(e => e.IsValid)
        .GroupedWithin(50, TimeSpan.FromMilliseconds(500))
        .SelectAsync(4, batch => ProcessBatchAsync(batch))
        .SelectMany(results => results)
        .ToMaterialized(sink, Keep.Right);
}
```

---

## Level 4b: Reactive Extensions (UI and Event Composition)

**Use for:** UI event handling, composing event streams, time-based operations in client applications.

```csharp
using System.Reactive.Linq;

public class SearchViewModel
{
    public SearchViewModel(ISearchService searchService)
    {
        SearchResults = SearchText
            .Throttle(TimeSpan.FromMilliseconds(300))
            .DistinctUntilChanged()
            .Where(text => text.Length >= 3)
            .SelectMany(text => searchService.SearchAsync(text).ToObservable())
            .ObserveOn(RxApp.MainThreadScheduler);
    }

    public IObservable<string> SearchText { get; }
    public IObservable<IList<SearchResult>> SearchResults { get; }
}

public IObservable<bool> CanSubmit =>
    Observable.CombineLatest(
        UsernameValid,
        PasswordValid,
        EmailValid,
        (user, pass, email) => user && pass && email);

public IObservable<Point> DoubleClicks =>
    MouseClicks
        .Buffer(TimeSpan.FromMilliseconds(300))
        .Where(clicks => clicks.Count >= 2)
        .Select(clicks => clicks.Last());

public IDisposable AutoSave =>
    DocumentChanges
        .Throttle(TimeSpan.FromSeconds(2))
        .Subscribe(async doc => await SaveAsync(doc));
```

**Rx vs Akka.NET Streams:**

| Scenario | Rx | Akka.NET Streams |
|----------|----|--------------------|
| UI events | Best choice | Overkill |
| Client-side composition | Best choice | Overkill |
| Server-side pipelines | Works but limited | Better backpressure |
| Distributed processing | Not designed for | Built for this |
| Hot observables | Native support | Requires more setup |

---

## Level 5: Akka.NET Actors (Stateful Concurrency)

**Use for:** Managing state for multiple entities, state machines, push-based updates, complex coordination, supervision and fault tolerance.

### Entity-Per-Actor Pattern

```csharp
public class OrderActor : ReceiveActor
{
    private OrderState _state;

    public OrderActor(string orderId)
    {
        _state = new OrderState(orderId);

        Receive<AddItem>(msg =>
        {
            _state = _state.AddItem(msg.Item);
            Sender.Tell(new ItemAdded(msg.Item));
        });

        Receive<Checkout>(msg =>
        {
            if (_state.CanCheckout)
            {
                _state = _state.Checkout();
                Sender.Tell(new CheckoutSucceeded(_state.Total));
            }
            else
            {
                Sender.Tell(new CheckoutFailed("Cart is empty"));
            }
        });

        Receive<GetState>(_ => Sender.Tell(_state));
    }
}
```

### State Machines with Become

```csharp
public class PaymentActor : ReceiveActor
{
    private PaymentData _payment;

    public PaymentActor(string paymentId)
    {
        _payment = new PaymentData(paymentId);
        Pending();
    }

    private void Pending()
    {
        Receive<AuthorizePayment>(msg =>
        {
            _payment = _payment with { Amount = msg.Amount };
            Become(Authorizing);
            Self.Tell(new ProcessAuthorization());
        });

        Receive<CancelPayment>(_ =>
        {
            Become(Cancelled);
            Sender.Tell(new PaymentCancelled(_payment.Id));
        });
    }

    private void Authorizing()
    {
        Receive<ProcessAuthorization>(async _ =>
        {
            var result = await _gateway.AuthorizeAsync(_payment);
            if (result.Success)
            {
                _payment = _payment with { AuthCode = result.AuthCode };
                Become(Authorized);
            }
            else
            {
                Become(Failed);
            }
        });

        Receive<CancelPayment>(_ =>
        {
            Sender.Tell(new PaymentError("Cannot cancel during authorization"));
        });
    }

    private void Authorized()
    {
        Receive<CapturePayment>(_ =>
        {
            Become(Capturing);
            Self.Tell(new ProcessCapture());
        });

        Receive<VoidPayment>(_ =>
        {
            Become(Voiding);
            Self.Tell(new ProcessVoid());
        });
    }

    private void Capturing() { }
    private void Voiding() { }
    private void Cancelled() { }
    private void Failed() { }
}
```

---

## Synchronization Primitives

When you must use shared mutable state, choose the simplest primitive that meets the requirement.

### Quick Reference Table

| Primitive | Async-Safe | Reentrant | Use Case |
|-----------|-----------|-----------|----------|
| `lock` / `Monitor` | No | Yes (same thread) | Short critical sections without `await` |
| `SemaphoreSlim` | Yes (`WaitAsync`) | No | Async-compatible mutual exclusion, throttling |
| `Interlocked` | N/A (lock-free) | N/A | Atomic scalar operations (increment, compare-exchange) |
| `ConcurrentDictionary<K,V>` | N/A (thread-safe) | N/A | Thread-safe key-value cache/lookup |
| `ConcurrentQueue<T>` | N/A (thread-safe) | N/A | Thread-safe FIFO queue |
| `ReaderWriterLockSlim` | No | Optional (`LockRecursionPolicy`) | Many-readers/few-writers (profile-driven only) |
| `SpinLock` | No | No | Ultra-short critical sections under extreme contention |

### lock and Monitor

```csharp
public sealed class Counter
{
    private readonly object _lock = new();
    private int _count;

    public void Increment()
    {
        lock (_lock)
        {
            _count++;
        }
    }

    public int GetCount()
    {
        lock (_lock)
        {
            return _count;
        }
    }
}
```

**Lock Object Rules:**
- Use a private, dedicated `object` field
- Never lock on `this`
- Never lock on `typeof(T)`
- Never lock on string literals
- Never lock on value types

### SemaphoreSlim

The only built-in .NET synchronization primitive that supports `await`:

```csharp
public sealed class AsyncCache
{
    private readonly SemaphoreSlim _semaphore = new(1, 1);
    private readonly Dictionary<string, object> _cache = new();

    public async Task<T> GetOrAddAsync<T>(string key,
        Func<CancellationToken, Task<T>> factory,
        CancellationToken ct = default)
    {
        await _semaphore.WaitAsync(ct);
        try
        {
            if (_cache.TryGetValue(key, out var existing))
                return (T)existing;

            var value = await factory(ct);
            _cache[key] = value!;
            return value;
        }
        finally
        {
            _semaphore.Release();
        }
    }
}
```

### Interlocked Operations

Lock-free atomic operations for scalar values:

```csharp
private int _counter;
private long _totalBytes;
private object? _current;

Interlocked.Increment(ref _counter);
Interlocked.Decrement(ref _counter);
Interlocked.Add(ref _totalBytes, bytesRead);
var previous = Interlocked.Exchange(ref _current, newValue);
var original = Interlocked.CompareExchange(ref _counter, newValue: 10, comparand: 0);
```

### ConcurrentDictionary

```csharp
private readonly ConcurrentDictionary<int, Widget> _cache = new();

var widget = _cache.GetOrAdd(id, key => LoadWidget(key));
var updated = _cache.AddOrUpdate(id,
    addValueFactory: key => CreateDefault(key),
    updateValueFactory: (key, existing) => existing with { LastAccessed = DateTime.UtcNow });

if (_cache.TryRemove(id, out var removed))
{
}
```

**Important:** `GetOrAdd` factory delegates may execute multiple times under contention. Use `Lazy<T>` wrapping for exactly-once semantics.

---

## Anti-Patterns: What to Avoid

### Locks for Business Logic

```csharp
// BAD: Using locks to protect shared state
private readonly object _lock = new();
private Dictionary<string, Order> _orders = new();

public void UpdateOrder(string id, Action<Order> update)
{
    lock (_lock)
    {
        if (_orders.TryGetValue(id, out var order))
        {
            update(order);
        }
    }
}

// GOOD: Use an actor or Channel to serialize access
```

### Blocking in Async Code

```csharp
// BAD: Blocking on async
var result = GetDataAsync().Result;
GetDataAsync().Wait();

// GOOD: Async all the way
var result = await GetDataAsync();
```

### Shared Mutable State Without Protection

```csharp
// BAD: Multiple tasks mutating shared state
var results = new List<Result>();
await Parallel.ForEachAsync(items, async (item, ct) =>
{
    var result = await ProcessAsync(item, ct);
    results.Add(result); // Race condition!
});

// GOOD: Use ConcurrentBag or collect results differently
var results = new ConcurrentBag<Result>();
```

### Do not use `lock` inside `async` methods

`lock` is thread-affine; the continuation after `await` may resume on a different thread, causing `SynchronizationLockException`. Use `SemaphoreSlim.WaitAsync` instead.

---

## Prefer Async Local Functions

Use async local functions instead of `Task.Run(async () => ...)` or `ContinueWith()`:

```csharp
private void HandleCommand(MyCommand cmd)
{
    async Task<WorkCompleted> ExecuteAsync()
    {
        var result = await DoWorkAsync();
        return new WorkCompleted(result);
    }

    ExecuteAsync().PipeTo(Self);
}
```

---

## Quick Reference: Which Tool When?

| Need | Tool | Example |
|------|------|---------|
| Wait for I/O | `async/await` | HTTP calls, database queries |
| Parallel CPU work | `Parallel.ForEachAsync` | Image processing, calculations |
| Work queue | `Channel<T>` | Background job processing |
| UI events with debounce/throttle | Reactive Extensions | Search-as-you-type, auto-save |
| Server-side batching/throttling | Akka.NET Streams | Event aggregation, rate limiting |
| State machines | Akka.NET Actors | Payment flows, order lifecycles |
| Entity state management | Akka.NET Actors | Order management, user sessions |
| Fire multiple async ops | `Task.WhenAll` | Loading dashboard data |
| Race multiple async ops | `Task.WhenAny` | Timeout with fallback |
| Periodic work | `PeriodicTimer` | Health checks, polling |
| Protect single scalar | `Interlocked` | Counters, flags |
| Protect key-value state | `ConcurrentDictionary` | Caches, lookups |
| Async-compatible mutex | `SemaphoreSlim` | Async critical sections |
| Simple synchronous mutex | `lock` | Short critical sections without `await` |

---

## The Escalation Path

```
async/await (start here)
    │
    ├─► Need parallelism? → Parallel.ForEachAsync
    │
    ├─► Need producer/consumer? → Channel<T>
    │
    ├─► Need UI event composition? → Reactive Extensions
    │
    ├─► Need server-side stream processing? → Akka.NET Streams
    │
    └─► Need state machines or entity management? → Akka.NET Actors
```

**Only escalate when you have a concrete need.** Don't reach for actors or streams "just in case" - start with async/await and move up only when the simpler approach doesn't fit.

---

## References

- [Threading in C# (Joseph Albahari)](https://www.albahari.com/threading/)
- [Concurrency in C# Cookbook (Stephen Cleary)](https://blog.stephencleary.com/)
- [System.Threading.Interlocked](https://learn.microsoft.com/dotnet/api/system.threading.interlocked)
- [ConcurrentDictionary best practices](https://learn.microsoft.com/dotnet/api/system.collections.concurrent.concurrentdictionary-2)
- [SemaphoreSlim class](https://learn.microsoft.com/dotnet/api/system.threading.semaphoreslim)
- [ReaderWriterLockSlim class](https://learn.microsoft.com/dotnet/api/system.threading.readwriterlockslim)
- [Pattern Matching](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/functional/pattern-matching)
- [Span<T> and Memory<T>](https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/)
- [Async Best Practices](https://learn.microsoft.com/en-us/archive/msdn-magazine/2013/march/async-await-best-practices-in-asynchronous-programming)
