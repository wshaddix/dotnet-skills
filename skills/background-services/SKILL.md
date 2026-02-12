---
name: background-services
description: Hosted services, background jobs, outbox patterns, and graceful shutdown handling for ASP.NET Core applications. Includes patterns for reliable job processing and distributed systems. Use when implementing background processing in ASP.NET Core applications, handling outbox patterns for reliable message delivery, or managing graceful service shutdown.
---

## Rationale

Background services are essential for offloading work from the request pipeline, processing queues, and handling scheduled tasks. Poorly implemented background services can lead to data loss, orphaned jobs, and resource leaks. These patterns ensure reliable, observable, and gracefully degrading background processing in production applications.

## Patterns

### Pattern 1: Basic Hosted Service Structure

Use `BackgroundService` base class for consistent lifecycle management and cancellation support.

```csharp
public class NotificationProcessor : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<NotificationProcessor> _logger;

    public NotificationProcessor(
        IServiceProvider serviceProvider,
        ILogger<NotificationProcessor> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Notification processor starting...");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = _serviceProvider.CreateAsyncScope();
                var queueService = scope.ServiceProvider.GetRequiredService<INotificationQueue>();

                var notification = await queueService.DequeueAsync(stoppingToken);
                if (notification is not null)
                {
                    await ProcessNotificationAsync(notification, stoppingToken);
                }
                else
                {
                    await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("Notification processor stopping...");
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing notification");
                await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
            }
        }
    }

    private async Task ProcessNotificationAsync(Notification notification, CancellationToken ct)
    {
        // Implementation
    }
}
```

### Pattern 2: Outbox Pattern for Reliable Messaging

Ensure messages are never lost by storing them in the database transactionally before async processing.

```csharp
// Outbox entity
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

// Repository pattern for outbox
public interface IOutboxRepository
{
    Task AddAsync(OutboxMessage message, CancellationToken ct = default);
    Task<IReadOnlyList<OutboxMessage>> GetPendingAsync(int batchSize, CancellationToken ct = default);
    Task MarkProcessedAsync(Guid messageId, CancellationToken ct = default);
    Task MarkFailedAsync(Guid messageId, string error, CancellationToken ct = default);
}

// During business operation - transactional
public class OrderService
{
    private readonly ApplicationDbContext _db;
    private readonly IOutboxRepository _outbox;

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        await using var transaction = await _db.Database.BeginTransactionAsync();

        try
        {
            // Create order
            var order = new Order { /* ... */ };
            _db.Orders.Add(order);

            // Add outbox message in same transaction
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

// Background processor for outbox
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

### Pattern 3: Graceful Shutdown Handling

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
        // Register shutdown handler
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
                // Re-queue or handle partial completion
                throw;
            }
        }
    }

    private async Task ProcessWorkItemAsync(WorkItem item, CancellationToken ct)
    {
        using var activity = new Activity("ProcessWorkItem").Start();
        _logger.LogInformation("Processing work item {WorkId}", item.Id);

        // Simulate work
        await Task.Delay(item.Duration, ct);

        _logger.LogInformation("Completed work item {WorkId}", item.Id);
    }
}

// Advanced: IHostedLifecycleService for complex scenarios
public class LifecycleAwareService : IHostedLifecycleService
{
    private readonly ILogger<LifecycleAwareService> _logger;

    public LifecycleAwareService(ILogger<LifecycleAwareService> logger)
    {
        _logger = logger;
    }

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

### Pattern 4: Scheduled Jobs with Cron Expressions

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
        // Run every day at 2 AM
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

// Configuration in Program.cs
builder.Services.AddHostedService<ScheduledJobService>();
```

### Pattern 5: Queue-Based Processing with Rate Limiting

Implement rate-limited background processing to prevent overwhelming downstream systems.

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
        _semaphore = new SemaphoreSlim(5, 5); // Max 5 concurrent
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

            // Clean up completed tasks periodically
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
            // Implement retry logic or dead letter queue
        }

        // Rate limit: wait before next email
        await Task.Delay(TimeSpan.FromMilliseconds(100), ct);
    }
}

// Registration
builder.Services.AddSingleton<RateLimitedProcessor>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<RateLimitedProcessor>());

// Usage in PageModel
public class ContactModel : PageModel
{
    private readonly RateLimitedProcessor _processor;

    public async Task<IActionResult> OnPostAsync()
    {
        await _processor.Writer.WriteAsync(new EmailRequest
        {
            To = Input.Email,
            Subject = "Thank you for contacting us"
        });

        return RedirectToPage("/Contact/Success");
    }
}
```

## Anti-Patterns

```csharp
// ❌ BAD: No cancellation token handling
public class BadProcessor : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (true) // Never stops!
        {
            await DoWorkAsync(); // No cancellation
        }
    }
}

// ✅ GOOD: Proper cancellation handling
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

// ❌ BAD: Swallowing all exceptions
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        try
        {
            await DoWorkAsync();
        }
        catch (Exception ex)
        {
            // Silently swallowed - service appears healthy but isn't working!
        }
    }
}

// ✅ GOOD: Log and continue with backoff
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
            break; // Expected during shutdown
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Work failed");
            await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
        }
    }
}

// ❌ BAD: Using scoped services without creating scope
public class BadService : BackgroundService
{
    private readonly ApplicationDbContext _db; // Scoped service in singleton!

    public BadService(ApplicationDbContext db) => _db = db;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var data = await _db.Orders.ToListAsync(ct); // Will fail after first request!
    }
}

// ✅ GOOD: Create scope for each unit of work
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

// ❌ BAD: Blocking async code
protected override Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        DoWork().Wait(); // Blocks thread!
    }
    return Task.CompletedTask;
}

// ✅ GOOD: Use async/await throughout
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        await DoWorkAsync(stoppingToken);
    }
}
```

## References

- [Hosted Services in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services)
- [Background tasks with IHostedService](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/multi-container-microservice-net-applications/background-tasks-with-ihostedservice)
- [NCrontab](https://github.com/atifaziz/NCrontab) - Cron scheduling library
- [Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)
- [Graceful Shutdown in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/hosting)
