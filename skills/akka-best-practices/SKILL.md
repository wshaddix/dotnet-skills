---
name: akka-net-best-practices
description: Critical Akka.NET best practices including EventStream vs DistributedPubSub, supervision strategies, error handling, Props vs DependencyResolver, work distribution patterns, and cluster/local mode abstractions for testability. Use when designing actor communication patterns, implementing error handling, choosing between Props and DependencyResolver, or creating testable actor systems.
---

# Akka.NET Best Practices

## When to Use This Skill

Use this skill when:
- Designing actor communication patterns
- Deciding between EventStream and DistributedPubSub
- Implementing error handling in actors
- Understanding supervision strategies
- Choosing between Props patterns and DependencyResolver
- Designing work distribution across nodes
- Creating testable actor systems that can run with or without cluster infrastructure
- Abstracting over Cluster Sharding for local testing scenarios

---

## Core Principles

### Communication Patterns

| Pattern | When to Use |
|---------|-------------|
| **EventStream** | Local-only events (logging, single-process apps) |
| **DistributedPubSub** | Cross-cluster pub/sub messaging |
| **Direct ActorRefs** | Point-to-point communication |
| **Outbox Pattern** | Reliable fire-and-forget to external systems |

### Error Handling Strategy

| Approach | When to Use |
|----------|-------------|
| **Try-Catch** | Expected failures (network timeouts, invalid input) |
| **Supervision** | Unknown failures, state corruption, programming errors |

### Actor Creation

| Approach | When to Use |
|----------|-------------|
| **Plain Props** | Simple actors without DI needs |
| **DependencyResolver** | Actors needing `IServiceProvider` or `IRequiredActor<T>` |

### Work Distribution

| Pattern | Use Case |
|---------|----------|
| **Database Queue** | Distribute work across nodes with `FOR UPDATE SKIP LOCKED` |
| **Akka.Streams** | Rate limiting within a single node |
| **Durable Outbox** | Reliable background job processing |

### Testing Abstractions

| Mode | Use Case |
|------|----------|
| **LocalTest** | Fast unit tests, single-node integration tests |
| **Clustered** | Production, multi-node integration tests |

---

## Reference Documentation

Detailed guides organized by topic:

1. **[Communication Patterns](reference/communication-patterns.md)** - EventStream vs DistributedPubSub, Topic Design Patterns, Work Distribution Patterns
2. **[Supervision and Error Handling](reference/supervision-error-handling.md)** - Supervision strategies, Error handling patterns
3. **[Actor Lifecycle](reference/actor-lifecycle.md)** - Props vs DependencyResolver, Cluster/Local mode abstractions, Actor logging, Managing async operations with CancellationToken
4. **[Quick Reference](reference/quick-reference.md)** - Common mistakes summary, Decision trees
