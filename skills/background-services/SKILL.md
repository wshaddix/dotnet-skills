---
name: background-services
description: Hosted services, background jobs, outbox patterns, and graceful shutdown handling for ASP.NET Core applications. Includes patterns for reliable job processing, distributed systems, and lifecycle management. Use when implementing background processing in ASP.NET Core applications, handling outbox patterns for reliable message delivery, or managing graceful service shutdown.
---

# Background Services in ASP.NET Core

## Rationale

Background services are essential for offloading work from the request pipeline, processing queues, and handling scheduled tasks. Poorly implemented background services can lead to data loss, orphaned jobs, and resource leaks. These patterns ensure reliable, observable, and gracefully degrading background processing in production applications.

---

## BackgroundService vs IHostedService

| Feature | `BackgroundService` | `IHostedService` |
|---------|-------------------|-----------------|
| Purpose | Long-running loop or continuous work | Startup/shutdown hooks |
| Methods | Override `ExecuteAsync` | Implement `StartAsync` + `StopAsync` |
| Lifetime | Runs until cancellation or host shutdown | `StartAsync` runs at startup, `StopAsync` at shutdown |
| Use when | Polling queues, processing streams, periodic jobs | Database migrations, cache warming, resource cleanup |

---

## Pattern 1: Basic BackgroundService Structure

Use `BackgroundService` base class for consistent lifecycle management and cancellation support.

```csharp
public sealed class OrderProcessorWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<OrderProcessorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Order processor started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var processor = scope.ServiceProvider
                    .GetRequiredService<IOrderProcessor>();

                var processed = await processor.ProcessPendingAsync(stoppingToken);

                if (processed == 0)
                {
                    await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing orders");
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
        }

        logger.LogInformation("Order processor stopped");
    }
}

// Registration
builder.Services.AddHostedService<OrderProcessorWorker>();
```

### Critical Rules for BackgroundService

1. **Always create scopes** -- `BackgroundService` is registered as a singleton. Inject `IServiceScopeFactory`, not scoped services directly.
2. **Always handle exceptions** -- by default, unhandled exceptions in `ExecuteAsync` stop the host. Wrap the loop body in try/catch.
3. **Always respect the stopping token** -- check `stoppingToken.IsCancellationRequested` and pass the token to all async calls.
4. **Back off on empty/error** -- avoid tight polling loops that waste CPU. Use `Task.Delay` with the stopping token.

---

## Pattern 2: IHostedService for Startup/Shutdown Hooks

### Startup Hook (Cache Warming, Migrations)

```csharp
public sealed class CacheWarmupService(
    IServiceScopeFactory scopeFactory,
    ILogger<CacheWarmupService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Warming caches");

        using var scope = scopeFactory.CreateScope();
        var cache = scope.ServiceProvider.GetRequiredService<IProductCache>();
        await cache.WarmAsync(cancellationToken);

        logger.LogInformation("Cache warmup complete");
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
```

### Startup + Shutdown (Resource Lifecycle)

```csharp
public sealed class MessageBusService(
    ILogger<MessageBusService> logger) : IHostedService
{
    private IConnection? _connection;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Connecting to message bus");
        _connection = await CreateConnectionAsync(cancellationToken);
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Disconnecting from message bus");
        if (_connection is not null)
        {
            await _connection.CloseAsync(cancellationToken);
            _connection = null;
        }
    }

    private static Task<IConnection> CreateConnectionAsync(CancellationToken ct) =>
        throw new NotImplementedException();
}
```

---

## Pattern 3: Hosted Service Lifecycle

### Startup Sequence

1. `IHostedService.StartAsync` is called for each registered service **in registration order**
2. `BackgroundService.ExecuteAsync` is called after `StartAsync` completes (it runs concurrently -- the host does not wait for it to finish)
3. The host is ready to serve requests after all `StartAsync` calls complete

**Important:** `ExecuteAsync` must not block before yielding to the caller. The first `await` in `ExecuteAsync` is where control returns to the host.

```csharp
public sealed class MyWorker : BackgroundService
{
    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await base.StartAsync(cancellationToken);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await DoWorkAsync(stoppingToken);
        }
    }
}
```

### Shutdown Sequence

1. `IHostApplicationLifetime.ApplicationStopping` is triggered
2. The host calls `StopAsync` on each hosted service **in reverse registration order**
3. For `BackgroundService`, the stopping token is cancelled, then `StopAsync` waits for `ExecuteAsync` to complete
4. `IHostApplicationLifetime.ApplicationStopped` is triggered

---

## Pattern 4: Outbox Pattern for Reliable Messaging

Ensure messages are never lost by storing them in the database transactionally before async processing.

```csharp
public class OutboxMessage
{
    public Guid Id { get; set; }
    public required string Type { get; set; }
    public required string Payload { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ProcessedAt { get; set; }
    public string? Error { get; set; }
    public int RetryCount { get; set; }
}

public interface IOutboxRepository
{
    Task AddAsync(OutboxMessage message, CancellationToken ct = default);
    Task<IReadOnlyList<OutboxMessage>> GetPendingAsync(int batchSize, CancellationToken ct = default);
    Task MarkProcessedAsync(Guid messageId, CancellationToken ct = default);
    Task MarkFailedAsync(Guid messageId, string error, CancellationToken ct = default);
}

public class OrderService
{
    private readonly ApplicationDbContext _db;
    private readonly IOutboxRepository _outbox;

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        await using var transaction = await _db.Database.BeginTransactionAsync();

        try
        {
            var order = new Order { };
            _db.Orders.Add(order);

            var message = new OutboxMessage
            {
                Id = Guid.NewGuid(),
                Type = nameof(OrderCreatedEvent),
                Payload = JsonSerializer.Serialize(new OrderCreatedEvent
                {
                    OrderId = order.Id,
                    CustomerEmail = request.CustomerEmail
                }),
                CreatedAt = DateTimeOffset.UtcNow
            };
            await _outbox.AddAsync(message);

            await _db.SaveChangesAsync();
            await transaction.CommitAsync();

            return order;
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }
}

public class OutboxProcessor : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<OutboxProcessor> _logger;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = _serviceProvider.CreateAsyncScope();
                var outbox = scope.ServiceProvider.GetRequiredService<IOutboxRepository>();
                var publisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();

                var messages = await outbox.GetPendingAsync(batchSize: 10, stoppingToken);

                foreach (var message in messages)
                {
                    try
                    {
                        await publisher.PublishAsync(message.Type, message.Payload, stoppingToken);
                        await outbox.MarkProcessedAsync(message.Id, stoppingToken);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to process outbox message {MessageId}", message.Id);
                        await outbox.MarkFailedAsync(message.Id, ex.Message, stoppingToken);
                    }
                }

                await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in outbox processor");
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
        }
    }
}
```

---

## Pattern 5: Graceful Shutdown Handling

Implement `IHostedLifecycleService` for fine-grained control over startup and shutdown sequences.

```csharp
public class GracefulWorker : BackgroundService
{
    private readonly IHostApplicationLifetime _lifetime;
    private readonly ILogger<GracefulWorker> _logger;
    private readonly Channel<WorkItem> _workChannel;

    public GracefulWorker(
        IHostApplicationLifetime lifetime,
        ILogger<GracefulWorker> logger)
    {
        _lifetime = lifetime;
        _logger = logger;
        _workChannel = Channel.CreateUnbounded<WorkItem>();
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _lifetime.ApplicationStopping.Register(() =>
        {
            _logger.LogInformation("Shutdown requested, draining work channel...");
        });

        await foreach (var workItem in _workChannel.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await ProcessWorkItemAsync(workItem, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                _logger.LogWarning("Work item {WorkId} cancelled due to shutdown", workItem.Id);
                throw;
            }
        }
    }

    private async Task ProcessWorkItemAsync(WorkItem item, CancellationToken ct)
    {
        using var activity = new Activity("ProcessWorkItem").Start();
        _logger.LogInformation("Processing work item {WorkId}", item.Id);
        await Task.Delay(item.Duration, ct);
        _logger.LogInformation("Completed work item {WorkId}", item.Id);
    }
}

public class LifecycleAwareService : IHostedLifecycleService
{
    private readonly ILogger<LifecycleAwareService> _logger;

    public LifecycleAwareService(ILogger<LifecycleAwareService> logger) => _logger = logger;

    public Task StartingAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Service starting...");
        return Task.CompletedTask;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Service start called");
        return Task.CompletedTask;
    }

    public Task StartedAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Service started successfully");
        return Task.CompletedTask;
    }

    public Task StoppingAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Service stopping - cleanup starting...");
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Service stop called");
        return Task.CompletedTask;
    }

    public Task StoppedAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Service stopped - cleanup complete");
        return Task.CompletedTask;
    }
}
```

### Host Shutdown Timeout

```csharp
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(60);
});
```

---

## Pattern 6: Channels Integration

Channel-backed background task queue consumed by a `BackgroundService`:

```csharp
public sealed class BackgroundTaskQueue
{
    private readonly Channel<Func<IServiceProvider, CancellationToken, Task>> _queue
        = Channel.CreateBounded<Func<IServiceProvider, CancellationToken, Task>>(
            new BoundedChannelOptions(100) { FullMode = BoundedChannelFullMode.Wait });

    public ChannelWriter<Func<IServiceProvider, CancellationToken, Task>> Writer => _queue.Writer;
    public ChannelReader<Func<IServiceProvider, CancellationToken, Task>> Reader => _queue.Reader;
}

public sealed class QueueProcessorWorker(
    BackgroundTaskQueue queue,
    IServiceScopeFactory scopeFactory,
    ILogger<QueueProcessorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (await queue.Reader.WaitToReadAsync(stoppingToken))
        {
            while (queue.Reader.TryRead(out var workItem))
            {
                try
                {
                    using var scope = scopeFactory.CreateScope();
                    await workItem(scope.ServiceProvider, stoppingToken);
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error executing queued work item");
                }
            }
        }
    }
}

// Registration
builder.Services.AddSingleton<BackgroundTaskQueue>();
builder.Services.AddHostedService<QueueProcessorWorker>();
```

---

## Pattern 7: Scheduled Jobs with Cron Expressions

Use NCrontab for reliable cron-based scheduling without external dependencies.

```csharp
public class ScheduledJobService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<ScheduledJobService> _logger;
    private readonly CrontabSchedule _schedule;
    private DateTime _nextRun;

    public ScheduledJobService(IServiceProvider serviceProvider, ILogger<ScheduledJobService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
        _schedule = CrontabSchedule.Parse("0 2 * * *");
        _nextRun = _schedule.GetNextOccurrence(DateTime.Now);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var now = DateTime.Now;
            if (now >= _nextRun)
            {
                try
                {
                    await ExecuteJobAsync(stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Scheduled job failed");
                }
                _nextRun = _schedule.GetNextOccurrence(now);
            }

            var delay = _nextRun - DateTime.Now;
            if (delay > TimeSpan.Zero)
            {
                await Task.Delay(delay, stoppingToken);
            }
        }
    }

    private async Task ExecuteJobAsync(CancellationToken ct)
    {
        await using var scope = _serviceProvider.CreateAsyncScope();
        var service = scope.ServiceProvider.GetRequiredService<IDailyReportService>();
        await service.GenerateDailyReportAsync(ct);
    }
}
```

---

## Pattern 8: Periodic Work with PeriodicTimer

Use `PeriodicTimer` instead of `Task.Delay` for more accurate periodic execution:

```csharp
public sealed class HealthCheckReporter(
    IServiceScopeFactory scopeFactory,
    ILogger<HealthCheckReporter> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var reporter = scope.ServiceProvider.GetRequiredService<IHealthReporter>();
                await reporter.ReportAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Health check report failed");
            }
        }
    }
}
```

---

## Pattern 9: Queue-Based Processing with Rate Limiting

```csharp
public class RateLimitedProcessor : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<RateLimitedProcessor> _logger;
    private readonly Channel<EmailRequest> _channel;
    private readonly SemaphoreSlim _semaphore;

    public RateLimitedProcessor(
        IServiceProvider serviceProvider,
        ILogger<RateLimitedProcessor> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
        _channel = Channel.CreateUnbounded<EmailRequest>();
        _semaphore = new SemaphoreSlim(5, 5);
    }

    public ChannelWriter<EmailRequest> Writer => _channel.Writer;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var processingTasks = new List<Task>();

        await foreach (var request in _channel.Reader.ReadAllAsync(stoppingToken))
        {
            await _semaphore.WaitAsync(stoppingToken);

            var task = ProcessWithReleaseAsync(request, stoppingToken);
            processingTasks.Add(task);

            if (processingTasks.Count > 100)
            {
                processingTasks.RemoveAll(t => t.IsCompleted);
            }
        }

        await Task.WhenAll(processingTasks);
    }

    private async Task ProcessWithReleaseAsync(EmailRequest request, CancellationToken ct)
    {
        try
        {
            await ProcessEmailAsync(request, ct);
        }
        finally
        {
            _semaphore.Release();
        }
    }

    private async Task ProcessEmailAsync(EmailRequest request, CancellationToken ct)
    {
        await using var scope = _serviceProvider.CreateAsyncScope();
        var emailService = scope.ServiceProvider.GetRequiredService<IEmailService>();

        try
        {
            await emailService.SendAsync(request, ct);
            _logger.LogInformation("Email sent to {Recipient}", request.To);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email to {Recipient}", request.To);
        }

        await Task.Delay(TimeSpan.FromMilliseconds(100), ct);
    }
}
```

---

## Anti-Patterns

```csharp
// BAD: No cancellation token handling
public class BadProcessor : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (true) // Never stops!
        {
            await DoWorkAsync();
        }
    }
}

// GOOD: Proper cancellation handling
public class GoodProcessor : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await DoWorkAsync(stoppingToken);
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }
}

// BAD: Swallowing all exceptions
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        try
        {
            await DoWorkAsync();
        }
        catch (Exception)
        {
            // Silently swallowed - service appears healthy but isn't working!
        }
    }
}

// GOOD: Log and continue with backoff
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        try
        {
            await DoWorkAsync(stoppingToken);
        }
        catch (OperationCanceledException)
        {
            break;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Work failed");
            await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
        }
    }
}

// BAD: Using scoped services without creating scope
public class BadService : BackgroundService
{
    private readonly ApplicationDbContext _db; // Scoped service in singleton!

    public BadService(ApplicationDbContext db) => _db = db;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var data = await _db.Orders.ToListAsync(ct); // Will fail after first request!
    }
}

// GOOD: Create scope for each unit of work
public class GoodService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;

    public GoodService(IServiceProvider sp) => _serviceProvider = sp;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await using var scope = _serviceProvider.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var data = await db.Orders.ToListAsync(ct);
    }
}

// BAD: Blocking async code
protected override Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        DoWork().Wait(); // Blocks thread!
    }
    return Task.CompletedTask;
}

// GOOD: Use async/await throughout
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        await DoWorkAsync(stoppingToken);
    }
}
```

---

## Agent Gotchas

1. **Do not inject scoped services into BackgroundService constructors** -- they are singletons. Always use `IServiceScopeFactory`.
2. **Do not use `Task.Run` for background work** -- use `BackgroundService` for proper lifecycle management and graceful shutdown.
3. **Do not swallow `OperationCanceledException`** -- let it propagate or re-check the stopping token.
4. **Do not use `Thread.Sleep`** -- use `await Task.Delay(duration, stoppingToken)` or `PeriodicTimer`.
5. **Do not forget to register** -- `AddHostedService<T>()` is required; merely implementing the interface does nothing.

---

## References

- [Background tasks with hosted services](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services)
- [BackgroundService](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.backgroundservice)
- [IHostedService interface](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.ihostedservice)
- [Generic host shutdown](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host#host-shutdown)
- [PeriodicTimer](https://learn.microsoft.com/en-us/dotnet/api/system.threading.periodictimer)
- [Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)
- [NCrontab](https://github.com/atifaziz/NCrontab)
