# Communication Patterns

## EventStream vs DistributedPubSub

### Critical: EventStream is LOCAL ONLY

`Context.System.EventStream` is **local to a single ActorSystem process**. It does NOT work across cluster nodes.

```csharp
// BAD: This only works on a single server
// When you add a second server, subscribers on server 2 won't receive events from server 1
Context.System.EventStream.Subscribe(Self, typeof(PostCreated));
Context.System.EventStream.Publish(new PostCreated(postId, authorId));
```

**When EventStream is appropriate:**
- Logging and diagnostics within a single process
- Local event bus for truly single-process applications
- Development/testing scenarios

### Use DistributedPubSub for Multi-Node

For events that must reach actors across multiple cluster nodes, use `Akka.Cluster.Tools.PublishSubscribe`:

```csharp
using Akka.Cluster.Tools.PublishSubscribe;

public class TimelineUpdatePublisher : ReceiveActor
{
    private readonly IActorRef _mediator;

    public TimelineUpdatePublisher()
    {
        // Get the DistributedPubSub mediator
        _mediator = DistributedPubSub.Get(Context.System).Mediator;

        Receive<PublishTimelineUpdate>(msg =>
        {
            // Publish to a topic - reaches all subscribers across all nodes
            _mediator.Tell(new Publish($"timeline:{msg.UserId}", msg.Update));
        });
    }
}

public class TimelineSubscriber : ReceiveActor
{
    public TimelineSubscriber(UserId userId)
    {
        var mediator = DistributedPubSub.Get(Context.System).Mediator;

        // Subscribe to user-specific topic
        mediator.Tell(new Subscribe($"timeline:{userId}", Self));

        Receive<TimelineUpdate>(update =>
        {
            // Handle the update - this works across cluster nodes
        });

        Receive<SubscribeAck>(ack =>
        {
            // Subscription confirmed
        });
    }
}
```

### Akka.Hosting Configuration for DistributedPubSub

```csharp
builder.WithDistributedPubSub(role: null); // Available on all roles, or specify a role
```

## Topic Design Patterns

| Pattern | Topic Format | Use Case |
|---------|--------------|----------|
| Per-user | `timeline:{userId}` | Timeline updates, notifications |
| Per-entity | `post:{postId}` | Post engagement updates |
| Broadcast | `system:announcements` | System-wide notifications |
| Role-based | `workers:rss-poller` | Work distribution |

---

## Work Distribution Patterns

### Problem: Thundering Herd

When you have many background jobs (RSS feeds, email sending, etc.), don't process them all at once:

```csharp
// BAD: Polls all feeds simultaneously on startup
public class BadRssCoordinator : ReceiveActor
{
    public BadRssCoordinator(IRssFeedRepository repo)
    {
        ReceiveAsync<StartPolling>(async _ =>
        {
            var feeds = await repo.GetAllFeedsAsync();
            foreach (var feed in feeds) // 2000 feeds = 2000 simultaneous HTTP requests
            {
                Context.ActorOf(RssFeedPollerActor.Props(feed.Url));
            }
        });
    }
}
```

### Pattern 1: Database-Driven Work Queue

Use the database as a work queue with `FOR UPDATE SKIP LOCKED`:

```csharp
public class RssPollerWorker : ReceiveActor
{
    public RssPollerWorker(IRssFeedRepository repo)
    {
        ReceiveAsync<PollBatch>(async _ =>
        {
            // Each worker claims a batch - naturally distributes across nodes
            var feeds = await repo.ClaimFeedsForPollingAsync(
                batchSize: 10,
                staleAfter: TimeSpan.FromMinutes(10));

            foreach (var feed in feeds)
            {
                try
                {
                    await PollFeed(feed);
                    await repo.MarkPolledAsync(feed.Id, success: true);
                }
                catch (Exception ex)
                {
                    await repo.MarkPolledAsync(feed.Id, success: false, error: ex.Message);
                }
            }

            // Schedule next batch
            Context.System.Scheduler.ScheduleTellOnce(
                TimeSpan.FromSeconds(5),
                Self,
                PollBatch.Instance,
                Self);
        });
    }
}
```

```sql
-- ClaimFeedsForPollingAsync implementation
UPDATE rss_feeds
SET status = 'processing',
    processing_started_at = NOW()
WHERE id IN (
    SELECT id FROM rss_feeds
    WHERE status = 'pending'
      AND (next_poll_at IS NULL OR next_poll_at <= NOW())
    ORDER BY next_poll_at NULLS FIRST
    LIMIT @batchSize
    FOR UPDATE SKIP LOCKED
)
RETURNING *;
```

**Benefits:**
- Naturally distributes work across multiple server nodes
- No coordination needed - database handles locking
- Easy to monitor (query the table)
- Survives server restarts

### Pattern 2: Akka.Streams for Rate Limiting

Use Akka.Streams to throttle processing within a single node:

```csharp
public class ThrottledRssProcessor : ReceiveActor
{
    public ThrottledRssProcessor(IRssFeedRepository repo)
    {
        var materializer = Context.System.Materializer();

        ReceiveAsync<StartProcessing>(async _ =>
        {
            await Source.From(await repo.GetPendingFeedsAsync())
                .Throttle(10, TimeSpan.FromSeconds(1)) // Max 10 per second
                .SelectAsync(4, async feed => // Max 4 concurrent
                {
                    await PollFeed(feed);
                    return feed;
                })
                .RunWith(Sink.Ignore<RssFeed>(), materializer);
        });
    }
}
```

### Pattern 3: Durable Queue (Email Outbox Pattern)

For work that must be reliably processed, use a database-backed outbox:

```csharp
// Enqueue work transactionally with business operation
public async Task CreatePostAsync(Post post)
{
    await using var transaction = await _db.BeginTransactionAsync();

    await _postStore.CreateAsync(post);

    // Enqueue notification emails in same transaction
    foreach (var follower in await _followStore.GetFollowersAsync(post.AuthorId))
    {
        await _emailOutbox.EnqueueAsync(new EmailJob
        {
            To = follower.Email,
            Template = "new-post",
            Data = JsonSerializer.Serialize(new { PostId = post.Id })
        });
    }

    await transaction.CommitAsync();
}

// Worker processes outbox
public class EmailOutboxWorker : ReceiveActor
{
    public EmailOutboxWorker(IEmailOutboxStore outbox, IEmailSender sender)
    {
        ReceiveAsync<ProcessBatch>(async _ =>
        {
            var batch = await outbox.ClaimBatchAsync(10);
            foreach (var job in batch)
            {
                try
                {
                    await sender.SendAsync(job);
                    await outbox.MarkSentAsync(job.Id);
                }
                catch (Exception ex)
                {
                    await outbox.MarkFailedAsync(job.Id, ex.Message);
                }
            }
        });
    }
}
```
