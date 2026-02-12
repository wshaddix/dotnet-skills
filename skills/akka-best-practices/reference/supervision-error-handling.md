# Supervision and Error Handling

## Supervision Strategies

### Key Clarification: Supervision is for CHILDREN

A supervision strategy defined on an actor dictates **how that actor supervises its children**, NOT how the actor itself is supervised.

```csharp
public class ParentActor : ReceiveActor
{
    // This strategy applies to children of ParentActor, NOT to ParentActor itself
    protected override SupervisorStrategy SupervisorStrategy()
    {
        return new OneForOneStrategy(
            maxNrOfRetries: 10,
            withinTimeRange: TimeSpan.FromSeconds(30),
            decider: ex => ex switch
            {
                ArithmeticException => Directive.Resume,
                NullReferenceException => Directive.Restart,
                ArgumentException => Directive.Stop,
                _ => Directive.Escalate
            });
    }
}
```

### Default Supervision Strategy

The default `OneForOneStrategy` already includes rate limiting:
- **10 restarts within 1 second** = actor is permanently stopped
- This prevents infinite restart loops

**You rarely need a custom strategy** unless you have specific requirements.

### When to Define Custom Supervision

**Good reasons:**
- Actor throws exceptions indicating irrecoverable state corruption → Restart
- Actor throws exceptions that should NOT cause restart (expected failures) → Resume
- Child failures should affect siblings → Use `AllForOneStrategy`
- Need different retry limits than the default

**Bad reasons:**
- "Just to be safe" - the default is already safe
- Don't understand what the actor does - understand it first

### Example: When Custom Supervision Makes Sense

```csharp
public class RssFeedCoordinator : ReceiveActor
{
    protected override SupervisorStrategy SupervisorStrategy()
    {
        return new OneForOneStrategy(
            maxNrOfRetries: -1, // Unlimited retries
            withinTimeRange: TimeSpan.FromMinutes(1),
            decider: ex => ex switch
            {
                // HTTP timeout - transient, resume and let the actor retry via its own timer
                HttpRequestException => Directive.Resume,

                // Feed URL permanently invalid - stop this child, don't restart forever
                InvalidFeedUrlException => Directive.Stop,

                // Unknown error - restart to clear potentially corrupt state
                _ => Directive.Restart
            });
    }
}
```

---

## Error Handling: Supervision vs Try-Catch

### When to Use Try-Catch (Most Cases)

**Use try-catch when:**
- The failure is **expected** (network timeout, invalid input, external service down)
- You know **exactly why** the exception occurred
- You can handle it **gracefully** (retry, return error response, log and continue)
- Restarting would **not help** (same error would occur again)

```csharp
public class RssFeedPollerActor : ReceiveActor
{
    public RssFeedPollerActor()
    {
        ReceiveAsync<PollFeed>(async msg =>
        {
            try
            {
                var feed = await _httpClient.GetStringAsync(msg.FeedUrl);
                var items = ParseFeed(feed);
                // Process items...
            }
            catch (HttpRequestException ex)
            {
                // Expected failure - log and schedule retry
                _log.Warning("Feed {Url} unavailable: {Error}", msg.FeedUrl, ex.Message);
                Context.System.Scheduler.ScheduleTellOnce(
                    TimeSpan.FromMinutes(5),
                    Self,
                    msg,
                    Self);
            }
            catch (XmlException ex)
            {
                // Invalid feed format - log and mark as bad
                _log.Error("Feed {Url} has invalid format: {Error}", msg.FeedUrl, ex.Message);
                Sender.Tell(new FeedPollResult.InvalidFormat(msg.FeedUrl));
            }
        });
    }
}
```

### When to Let Supervision Handle It

**Let exceptions propagate (trigger supervision) when:**
- You have **no idea** why the exception occurred
- The actor's **state might be corrupt**
- A **restart would help** (fresh state, reconnect resources)
- It's a **programming error** (NullReferenceException, InvalidOperationException from bad logic)

```csharp
public class OrderActor : ReceiveActor
{
    private OrderState _state;

    public OrderActor()
    {
        Receive<ProcessPayment>(msg =>
        {
            // If this throws, we have no idea why - let supervision restart us
            // A restart will reload state from persistence and might fix the issue
            var result = _state.ApplyPayment(msg.Amount);
            Persist(new PaymentApplied(msg.Amount), evt =>
            {
                _state = _state.With(evt);
            });
        });
    }
}
```

### Anti-Pattern: Swallowing Unknown Exceptions

```csharp
// BAD: Swallowing exceptions hides problems
public class BadActor : ReceiveActor
{
    public BadActor()
    {
        ReceiveAsync<DoWork>(async msg =>
        {
            try
            {
                await ProcessWork(msg);
            }
            catch (Exception ex)
            {
                // This hides all errors - you'll never know something is broken
                _log.Error(ex, "Error processing work");
                // Actor continues with potentially corrupt state
            }
        });
    }
}

// GOOD: Handle known exceptions, let unknown ones propagate
public class GoodActor : ReceiveActor
{
    public GoodActor()
    {
        ReceiveAsync<DoWork>(async msg =>
        {
            try
            {
                await ProcessWork(msg);
            }
            catch (HttpRequestException ex)
            {
                // Known, expected failure - handle gracefully
                _log.Warning("HTTP request failed: {Error}", ex.Message);
                Sender.Tell(new WorkResult.TransientFailure());
            }
            // Unknown exceptions propagate to supervision
        });
    }
}
```
