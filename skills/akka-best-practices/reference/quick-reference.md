# Quick Reference

## Common Mistakes Summary

| Mistake | Why It's Wrong | Fix |
|---------|----------------|-----|
| Using EventStream for cross-node pub/sub | EventStream is local only | Use DistributedPubSub |
| Defining supervision to "protect" an actor | Supervision protects children | Understand the hierarchy |
| Catching all exceptions | Hides bugs, corrupts state | Only catch expected errors |
| Always using DependencyResolver | Adds unnecessary complexity | Use plain Props when possible |
| Processing all background jobs at once | Thundering herd, resource exhaustion | Use database queue + rate limiting |
| Throwing exceptions for expected failures | Triggers unnecessary restarts | Return result types, use messaging |

---

## Decision Trees

### Communication Pattern Decision Tree

```
Need to communicate between actors?
├── Same process only? → EventStream is fine
├── Across cluster nodes?
│   ├── Point-to-point? → Use ActorSelection or known IActorRef
│   └── Pub/sub? → Use DistributedPubSub
└── Fire-and-forget to external system? → Consider outbox pattern
```

### Error Handling Decision Tree

```
Exception occurred in actor?
├── Expected failure (HTTP timeout, invalid input)?
│   └── Try-catch, handle gracefully, continue
├── State might be corrupt?
│   └── Let supervision restart
├── Unknown cause?
│   └── Let supervision restart
└── Programming error (null ref, bad logic)?
    └── Let supervision restart, fix the bug
```

### Props Decision Tree

```
Creating actor Props?
├── Actor needs IServiceProvider?
│   └── Use resolver.Props<T>()
├── Actor needs IRequiredActor<T>?
│   └── Use resolver.Props<T>()
├── Simple actor with constructor params?
│   └── Use Props.Create(() => new Actor(...))
└── Remote deployment needed?
    └── Probably not - use cluster sharding instead
```
