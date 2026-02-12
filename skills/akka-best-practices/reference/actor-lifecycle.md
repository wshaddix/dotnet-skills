# Actor Lifecycle Patterns

## Props vs DependencyResolver

### When to Use Plain Props

**Use `Props.Create()` when:**
- Actor doesn't need `IServiceProvider` or `IRequiredActor<T>`
- All dependencies can be passed via constructor
- Actor is simple and self-contained

```csharp
// Simple actor with no DI needs
public static Props Props(PostId postId, IPostWriteStore store)
    => Akka.Actor.Props.Create(() => new PostEngagementActor(postId, store));

// Usage
var actor = Context.ActorOf(PostEngagementActor.Props(postId, store), postId.ToString());
```

### When to Use DependencyResolver

**Use `resolver.Props<T>()` when:**
- Actor needs `IServiceProvider` to create scoped services
- Actor uses `IRequiredActor<T>` to get references to other actors
- Actor has many dependencies that are already in DI container

```csharp
// Actor that needs scoped database connections
public class OrderProcessorActor : ReceiveActor
{
    public OrderProcessorActor(IServiceProvider serviceProvider)
    {
        ReceiveAsync<ProcessOrder>(async msg =>
        {
            // Create a scope for this operation
            using var scope = serviceProvider.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<OrderDbContext>();
            // Process order...
        });
    }
}

// Registration with DI
builder.WithActors((system, registry, resolver) =>
{
    var actor = system.ActorOf(resolver.Props<OrderProcessorActor>(), "order-processor");
    registry.Register<OrderProcessorActor>(actor);
});
```

### Remote Deployment Considerations

**You almost never need remote deployment.** Remote deployment means deploying an actor to run on a different node than the one creating it.

If you're not doing remote deployment (and you probably aren't):
- `Props.Create(() => new Actor(...))` with closures is fine
- The "serialization issue" warning doesn't apply

**When you would use remote deployment:**
- Distributing compute-intensive work to specific nodes
- Running actors on nodes with specific hardware (GPU, etc.)

For most applications, use **cluster sharding** instead of remote deployment - it handles distribution automatically.

---

## Cluster/Local Mode Abstractions

For applications that need to run both in clustered production environments and local/test environments without cluster infrastructure, use abstraction patterns to toggle between implementations.

### AkkaExecutionMode Enum

Define an execution mode that controls which implementations are used:

```csharp
/// <summary>
/// Determines how Akka.NET infrastructure features are configured.
/// </summary>
public enum AkkaExecutionMode
{
    /// <summary>
    /// Local test mode - no cluster infrastructure.
    /// Uses in-memory implementations for pub/sub and local parent actors
    /// instead of cluster sharding.
    /// </summary>
    LocalTest,

    /// <summary>
    /// Full cluster mode with sharding, singletons, and distributed pub/sub.
    /// </summary>
    Clustered
}
```

### GenericChildPerEntityParent - Local Sharding Alternative

When testing locally, you can't use Cluster Sharding. This actor mimics sharding behavior by creating child actors per entity ID using the same `IMessageExtractor` interface:

```csharp
/// <summary>
/// A local parent actor that mimics Cluster Sharding behavior.
/// Creates and manages child actors per entity ID using the same IMessageExtractor
/// that would be used with real sharding, enabling seamless switching between modes.
/// </summary>
public sealed class GenericChildPerEntityParent : ReceiveActor
{
    private readonly IMessageExtractor _extractor;
    private readonly Func<string, Props> _propsFactory;
    private readonly Dictionary<string, IActorRef> _children = new();
    private readonly ILoggingAdapter _log = Context.GetLogger();

    public GenericChildPerEntityParent(
        IMessageExtractor extractor,
        Func<string, Props> propsFactory)
    {
        _extractor = extractor;
        _propsFactory = propsFactory;

        ReceiveAny(msg =>
        {
            var entityId = _extractor.EntityId(msg);
            if (string.IsNullOrEmpty(entityId))
            {
                _log.Warning("Could not extract entity ID from message {0}", msg.GetType().Name);
                Unhandled(msg);
                return;
            }

            var child = GetOrCreateChild(entityId);

            // Unwrap the message if it's a ShardingEnvelope
            var unwrapped = _extractor.EntityMessage(msg);
            child.Forward(unwrapped);
        });
    }

    private IActorRef GetOrCreateChild(string entityId)
    {
        if (_children.TryGetValue(entityId, out var existing))
            return existing;

        var props = _propsFactory(entityId);
        var child = Context.ActorOf(props, entityId);
        Context.Watch(child);
        _children[entityId] = child;

        _log.Debug("Created child actor for entity {0}", entityId);
        return child;
    }

    protected override void PreRestart(Exception reason, object message)
    {
        // Don't stop children on restart
    }

    public static Props CreateProps(
        IMessageExtractor extractor,
        Func<string, Props> propsFactory)
    {
        return Props.Create(() => new GenericChildPerEntityParent(extractor, propsFactory));
    }
}
```

### IPubSubMediator - Abstracting DistributedPubSub

Create an interface to abstract over pub/sub so tests can use a local implementation:

```csharp
/// <summary>
/// Abstraction over pub/sub messaging that allows swapping between
/// DistributedPubSub (clustered) and local implementations (testing).
/// </summary>
public interface IPubSubMediator
{
    /// <summary>
    /// Subscribe an actor to a topic.
    /// </summary>
    void Subscribe(string topic, IActorRef subscriber);

    /// <summary>
    /// Unsubscribe an actor from a topic.
    /// </summary>
    void Unsubscribe(string topic, IActorRef subscriber);

    /// <summary>
    /// Publish a message to all subscribers of a topic.
    /// </summary>
    void Publish(string topic, object message);

    /// <summary>
    /// Send a message to one subscriber of a topic (load balanced).
    /// </summary>
    void Send(string topic, object message);
}
```

### LocalPubSubMediator - In-Memory Implementation

```csharp
/// <summary>
/// In-memory pub/sub implementation for local testing without cluster.
/// Uses the EventStream internally for simplicity.
/// </summary>
public sealed class LocalPubSubMediator : IPubSubMediator
{
    private readonly ActorSystem _system;
    private readonly ConcurrentDictionary<string, HashSet<IActorRef>> _subscriptions = new();
    private readonly object _lock = new();

    public LocalPubSubMediator(ActorSystem system)
    {
        _system = system;
    }

    public void Subscribe(string topic, IActorRef subscriber)
    {
        lock (_lock)
        {
            var subs = _subscriptions.GetOrAdd(topic, _ => new HashSet<IActorRef>());
            subs.Add(subscriber);
        }

        // Send acknowledgement like real DistributedPubSub does
        subscriber.Tell(new SubscribeAck(new Subscribe(topic, subscriber)));
    }

    public void Unsubscribe(string topic, IActorRef subscriber)
    {
        lock (_lock)
        {
            if (_subscriptions.TryGetValue(topic, out var subs))
            {
                subs.Remove(subscriber);
            }
        }

        subscriber.Tell(new UnsubscribeAck(new Unsubscribe(topic, subscriber)));
    }

    public void Publish(string topic, object message)
    {
        HashSet<IActorRef> subscribers;
        lock (_lock)
        {
            if (!_subscriptions.TryGetValue(topic, out var subs))
                return;
            subscribers = new HashSet<IActorRef>(subs);
        }

        foreach (var subscriber in subscribers)
        {
            subscriber.Tell(message);
        }
    }

    public void Send(string topic, object message)
    {
        IActorRef? target = null;
        lock (_lock)
        {
            if (_subscriptions.TryGetValue(topic, out var subs) && subs.Count > 0)
            {
                // Simple round-robin - pick first available
                target = subs.FirstOrDefault();
            }
        }

        target?.Tell(message);
    }
}
```

### ClusterPubSubMediator - Production Implementation

```csharp
/// <summary>
/// Production implementation wrapping Akka.Cluster.Tools.PublishSubscribe.
/// </summary>
public sealed class ClusterPubSubMediator : IPubSubMediator
{
    private readonly IActorRef _mediator;

    public ClusterPubSubMediator(ActorSystem system)
    {
        _mediator = DistributedPubSub.Get(system).Mediator;
    }

    public void Subscribe(string topic, IActorRef subscriber)
    {
        _mediator.Tell(new Subscribe(topic, subscriber));
    }

    public void Unsubscribe(string topic, IActorRef subscriber)
    {
        _mediator.Tell(new Unsubscribe(topic, subscriber));
    }

    public void Publish(string topic, object message)
    {
        _mediator.Tell(new Publish(topic, message));
    }

    public void Send(string topic, object message)
    {
        _mediator.Tell(new Send(topic, message, localAffinity: true));
    }
}
```

### Wiring It All Together

Configure your ActorSystem based on execution mode:

```csharp
public static class AkkaHostingExtensions
{
    public static AkkaConfigurationBuilder ConfigureActorSystem(
        this AkkaConfigurationBuilder builder,
        AkkaExecutionMode mode,
        IServiceCollection services)
    {
        if (mode == AkkaExecutionMode.Clustered)
        {
            builder
                .WithClustering()
                .WithShardRegion<MyEntity>(
                    "my-entity",
                    (system, registry, resolver) => entityId =>
                        resolver.Props<MyEntityActor>(entityId),
                    new MyEntityMessageExtractor(),
                    new ShardOptions())
                .WithDistributedPubSub();

            // Register cluster pub/sub mediator
            services.AddSingleton<IPubSubMediator>(sp =>
            {
                var system = sp.GetRequiredService<ActorSystem>();
                return new ClusterPubSubMediator(system);
            });
        }
        else // LocalTest mode
        {
            // Register local pub/sub mediator
            services.AddSingleton<IPubSubMediator>(sp =>
            {
                var system = sp.GetRequiredService<ActorSystem>();
                return new LocalPubSubMediator(system);
            });

            // Use GenericChildPerEntityParent instead of sharding
            builder.WithActors((system, registry, resolver) =>
            {
                var parent = system.ActorOf(
                    GenericChildPerEntityParent.CreateProps(
                        new MyEntityMessageExtractor(),
                        entityId => resolver.Props<MyEntityActor>(entityId)),
                    "my-entity");

                registry.Register<MyEntityParent>(parent);
            });
        }

        return builder;
    }
}
```

### Usage in Application Code

Application code uses the abstractions and doesn't need to know which mode is active:

```csharp
public class MyService
{
    private readonly IPubSubMediator _pubSub;
    private readonly IRequiredActor<MyEntityParent> _entityParent;

    public MyService(
        IPubSubMediator pubSub,
        IRequiredActor<MyEntityParent> entityParent)
    {
        _pubSub = pubSub;
        _entityParent = entityParent;
    }

    public async Task ProcessAsync(string entityId, MyCommand command)
    {
        // Works identically in both modes
        var parent = await _entityParent.GetAsync();
        parent.Tell(new ShardingEnvelope(entityId, command));

        // Publish event - works with both local and distributed pub/sub
        _pubSub.Publish($"entity:{entityId}", new EntityUpdated(entityId));
    }
}
```

### Benefits of This Pattern

| Benefit | Description |
|---------|-------------|
| **Fast unit tests** | No cluster startup overhead, tests run in milliseconds |
| **Identical message flow** | Same `IMessageExtractor`, same message types |
| **Easy debugging** | Local mode is simpler to step through |
| **Integration test flexibility** | Choose mode per test scenario |
| **Production confidence** | Abstractions are thin wrappers over real implementations |

### When to Use Each Mode

| Scenario | Recommended Mode |
|----------|------------------|
| Unit tests | LocalTest |
| Integration tests (single node) | LocalTest |
| Integration tests (multi-node) | Clustered |
| Local development | LocalTest or Clustered (your choice) |
| Production | Clustered |

---

## Actor Logging

### Use ILoggingAdapter, Not ILogger<T>

In actors, use `ILoggingAdapter` from `Context.GetLogger()` instead of DI-injected `ILogger<T>`:

```csharp
public class MyActor : ReceiveActor
{
    private readonly ILoggingAdapter _log = Context.GetLogger();

    public MyActor()
    {
        Receive<MyMessage>(msg =>
        {
            // ✅ Akka.NET ILoggingAdapter with semantic logging (v1.5.57+)
            _log.Info("Processing message for user {UserId}", msg.UserId);
            _log.Error(ex, "Failed to process {MessageType}", msg.GetType().Name);
        });
    }
}
```

**Why ILoggingAdapter:**
- Integrates with Akka's logging pipeline and supervision
- Supports semantic/structured logging as of v1.5.57
- Method names: `Info()`, `Debug()`, `Warning()`, `Error()` (not `Log*` variants)
- No DI required - obtained directly from actor context

**Don't inject ILogger<T>:**

```csharp
// ❌ Don't inject ILogger<T> into actors
public class MyActor : ReceiveActor
{
    private readonly ILogger<MyActor> _logger; // Wrong!

    public MyActor(ILogger<MyActor> logger)
    {
        _logger = logger;
    }
}
```

### Semantic Logging (v1.5.57+)

As of Akka.NET v1.5.57, `ILoggingAdapter` supports semantic/structured logging with named placeholders:

```csharp
// Named placeholders for better log aggregation and querying
_log.Info("Order {OrderId} processed for customer {CustomerId}", order.Id, order.CustomerId);

// Prefer named placeholders over positional
// ✅ Good: {OrderId}, {CustomerId}
// ❌ Avoid: {0}, {1}
```

---

## Managing Async Operations with CancellationToken

When actors launch async operations via `PipeTo`, those operations can outlive the actor if not properly managed. Use `CancellationToken` tied to the actor lifecycle.

### Actor-Scoped CancellationTokenSource

Cancel in-flight async work when the actor stops:

```csharp
public class DataSyncActor : ReceiveActor
{
    private CancellationTokenSource? _operationCts;

    public DataSyncActor()
    {
        ReceiveAsync<StartSync>(HandleStartSyncAsync);
    }

    protected override void PostStop()
    {
        // Cancel any in-flight async work when actor stops
        _operationCts?.Cancel();
        _operationCts?.Dispose();
        _operationCts = null;
        base.PostStop();
    }

    private Task HandleStartSyncAsync(StartSync cmd)
    {
        // Cancel any previous operation, create new CTS
        _operationCts?.Cancel();
        _operationCts?.Dispose();
        _operationCts = new CancellationTokenSource();
        var ct = _operationCts.Token;

        async Task<SyncResult> PerformSyncAsync()
        {
            try
            {
                ct.ThrowIfCancellationRequested();

                // Pass token to all async operations
                var data = await _repository.GetDataAsync(ct);
                await _service.ProcessAsync(data, ct);

                return new SyncResult(Success: true);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                // Actor is stopping - graceful exit
                return new SyncResult(Success: false, "Cancelled");
            }
        }

        PerformSyncAsync().PipeTo(Self);
        return Task.CompletedTask;
    }
}
```

### Linked CTS for Per-Operation Timeouts

For external API calls that might hang, use linked CTS with short timeouts:

```csharp
private static readonly TimeSpan ApiTimeout = TimeSpan.FromSeconds(30);

async Task<SyncResult> PerformSyncAsync()
{
    // Check actor-level cancellation
    ct.ThrowIfCancellationRequested();

    // Per-operation timeout linked to actor's CTS
    SomeResult result;
    using (var opCts = CancellationTokenSource.CreateLinkedTokenSource(ct))
    {
        opCts.CancelAfter(ApiTimeout);
        result = await _externalApi.FetchDataAsync(opCts.Token);
    }

    // Process result...
}
```

**How linked CTS works:**
- Inherits cancellation from parent (actor stop → cancels immediately)
- Adds its own timeout via `CancelAfter` (hung API → cancels after timeout)
- Whichever fires first wins
- Disposed after each operation (short-lived)

### Graceful Timeout vs Shutdown Handling

Distinguish between actor shutdown and operation timeout:

```csharp
try
{
    using var opCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
    opCts.CancelAfter(ApiTimeout);
    await _api.CallAsync(opCts.Token);
}
catch (OperationCanceledException) when (!ct.IsCancellationRequested)
{
    // Timeout (not actor death) - can retry or handle gracefully
    _log.Warning("API call timed out, skipping item");
}
// If ct.IsCancellationRequested is true, let it propagate up
```

### Key Points

| Practice | Description |
|----------|-------------|
| **Actor CTS in PostStop** | Always cancel and dispose in `PostStop()` |
| **New CTS per operation** | Cancel previous before starting new work |
| **Pass token everywhere** | EF Core queries, HTTP calls, etc. all accept `CancellationToken` |
| **Linked CTS for timeouts** | External calls get short timeouts to prevent hanging |
| **Check in loops** | Call `ct.ThrowIfCancellationRequested()` between iterations |
| **Graceful handling** | Distinguish timeout vs shutdown in catch blocks |

### When to Use

- Any actor that launches async work via `PipeTo`
- Long-running operations (sync jobs, batch processing)
- External API calls that might hang
- Database operations in loops
