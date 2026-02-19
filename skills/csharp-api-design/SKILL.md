---
name: api-design
description: Design stable, compatible public APIs using extend-only design principles. Manage API compatibility, wire compatibility, versioning, naming conventions, parameter ordering, and return types for NuGet packages and distributed systems. Use when designing public APIs for NuGet packages or libraries, making changes to existing public APIs, planning wire format changes for distributed systems, or reviewing pull requests for breaking changes.
---

# Public API Design and Compatibility

## When to Use This Skill

Use this skill when:
- Designing public APIs for NuGet packages or libraries
- Making changes to existing public APIs
- Planning wire format changes for distributed systems
- Implementing versioning strategies
- Reviewing pull requests for breaking changes

---

## The Three Types of Compatibility

| Type | Definition | Scope |
|------|------------|-------|
| **API/Source** | Code compiles against newer version | Public method signatures, types |
| **Binary** | Compiled code runs against newer version | Assembly layout, method tokens |
| **Wire** | Serialized data readable by other versions | Network protocols, persistence formats |

Breaking any of these creates upgrade friction for users.

---

## Extend-Only Design

The foundation of stable APIs: **never remove or modify, only extend**.

### Three Pillars

1. **Previous functionality is immutable** - Once released, behavior and signatures are locked
2. **New functionality through new constructs** - Add overloads, new types, opt-in features
3. **Removal only after deprecation period** - Years, not releases

### Benefits

- Old code continues working in new versions
- New and old pathways coexist
- Upgrades are non-breaking by default
- Users upgrade on their schedule

---

## Naming Conventions for API Surface

### Type Naming

| Type Kind | Suffix Pattern | Example |
|-----------|---------------|---------|
| Base class | `Base` suffix only for abstract base types | `ValidatorBase` |
| Interface | `I` prefix | `IWidgetFactory` |
| Exception | `Exception` suffix | `WidgetNotFoundException` |
| Attribute | `Attribute` suffix | `RequiredPermissionAttribute` |
| Event args | `EventArgs` suffix | `WidgetCreatedEventArgs` |
| Options/config | `Options` suffix | `WidgetServiceOptions` |
| Builder | `Builder` suffix | `WidgetBuilder` |

### Method Naming

| Pattern | Convention | Example |
|---------|-----------|---------|
| Synchronous | Verb or verb phrase | `Calculate()`, `GetWidget()` |
| Asynchronous | `Async` suffix | `CalculateAsync()`, `GetWidgetAsync()` |
| Boolean query | `Is`/`Has`/`Can` prefix | `IsValid()`, `HasPermission()` |
| Try pattern | `Try` prefix, `out` parameter | `TryGetWidget(int id, out Widget widget)` |
| Factory | `Create` prefix | `CreateWidget()`, `CreateWidgetAsync()` |
| Conversion | `To`/`From` prefix | `ToDto()`, `FromEntity()` |

### Avoid Abbreviations in Public API

```csharp
// WRONG -- abbreviations in public surface
public IReadOnlyList<TxnResult> GetRecentTxns(int cnt);

// CORRECT -- spelled out for clarity
public IReadOnlyList<TransactionResult> GetRecentTransactions(int count);
```

---

## Parameter Ordering

Consistent parameter ordering reduces cognitive load.

### Standard Order

1. **Target/subject** -- the primary entity being operated on
2. **Required parameters** -- essential inputs without defaults
3. **Optional parameters** -- inputs with sensible defaults
4. **Cancellation token** -- always last (convention enforced by CA1068)

```csharp
public Task<Widget> GetWidgetAsync(
    int widgetId,                              // 1. Target
    WidgetOptions options,                     // 2. Required
    bool includeHistory = false,               // 3. Optional
    CancellationToken cancellationToken = default); // 4. Always last
```

### Overload Progression

```csharp
// Simple -- sensible defaults
public Task<Widget> GetWidgetAsync(int widgetId,
    CancellationToken cancellationToken = default)
    => GetWidgetAsync(widgetId, WidgetOptions.Default, cancellationToken);

// Detailed -- full control
public Task<Widget> GetWidgetAsync(int widgetId,
    WidgetOptions options,
    CancellationToken cancellationToken = default);
```

---

## Return Type Selection

### When to Return What

| Scenario | Return Type | Rationale |
|----------|------------|-----------|
| Single entity, always exists | `Widget` | Throw if not found |
| Single entity, may not exist | `Widget?` | Nullable communicates optionality |
| Collection, possibly empty | `IReadOnlyList<Widget>` | Immutable, indexable, communicates no mutation |
| Streaming results | `IAsyncEnumerable<Widget>` | Avoids buffering entire result set |
| Operation result with detail | `Result<Widget>` / discriminated union | Rich error info without exceptions |
| Void with async | `Task` | Never `async void` except event handlers |
| Frequently synchronous completion | `ValueTask<Widget>` | Avoids Task allocation on cache hits |

### Prefer IReadOnlyList Over IEnumerable

```csharp
// WRONG -- caller does not know if result is materialized or lazy
public IEnumerable<Widget> GetWidgets();

// CORRECT -- signals materialized, indexable collection
public IReadOnlyList<Widget> GetWidgets();

// CORRECT -- signals streaming/lazy evaluation explicitly
public IAsyncEnumerable<Widget> GetWidgetsStreamAsync(
    CancellationToken cancellationToken = default);
```

### The Try Pattern

```csharp
public bool TryGetWidget(int widgetId, [NotNullWhen(true)] out Widget? widget);

public Task<Widget?> TryGetWidgetAsync(int widgetId,
    CancellationToken cancellationToken = default);
```

---

## Error Reporting Strategies

### Exception Hierarchy

```csharp
public class WidgetServiceException : Exception
{
    public WidgetServiceException(string message) : base(message) { }
    public WidgetServiceException(string message, Exception inner) : base(message, inner) { }
}

public class WidgetNotFoundException : WidgetServiceException
{
    public int WidgetId { get; }
    public WidgetNotFoundException(int widgetId)
        : base($"Widget {widgetId} not found.") => WidgetId = widgetId;
}

public class WidgetValidationException : WidgetServiceException
{
    public IReadOnlyList<string> Errors { get; }
    public WidgetValidationException(IReadOnlyList<string> errors)
        : base("Widget validation failed.") => Errors = errors;
}
```

### When to Use Exceptions vs Return Values

| Approach | When to Use |
|----------|------------|
| Throw exception | Unexpected failures, programming errors, infrastructure failures |
| Return `null` / `default` | "Not found" is a normal, expected outcome |
| Try pattern (`bool` + `out`) | Parsing or validation where failure is common and synchronous |
| Result object | Multiple failure modes that callers need to distinguish |

### Argument Validation

```csharp
public Widget CreateWidget(string name, decimal price)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(name);
    ArgumentOutOfRangeException.ThrowIfNegativeOrZero(price);

    return new Widget(name, price);
}
```

---

## API Change Guidelines

### Safe Changes (Any Release)

```csharp
// ADD new overloads with default parameters
public void Process(Order order, CancellationToken ct = default);

// ADD new optional parameters to existing methods
public void Send(Message msg, Priority priority = Priority.Normal);

// ADD new types, interfaces, enums
public interface IOrderValidator { }
public enum OrderStatus { Pending, Complete, Cancelled }

// ADD new members to existing types
public class Order
{
    public DateTimeOffset? ShippedAt { get; init; }  // NEW
}
```

### Unsafe Changes (Never or Major Version Only)

```csharp
// REMOVE or RENAME public members
public void ProcessOrder(Order order);  // Was: Process()

// CHANGE parameter types or order
public void Process(int orderId);  // Was: Process(Order order)

// CHANGE return types
public Order? GetOrder(string id);  // Was: public Order GetOrder()

// CHANGE access modifiers
internal class OrderProcessor { }  // Was: public

// ADD required parameters without defaults
public void Process(Order order, ILogger logger);  // Breaks callers!
```

### Deprecation Pattern

```csharp
// Step 1: Mark as obsolete with version
[Obsolete("Obsolete since v1.5.0. Use ProcessAsync instead.")]
public void Process(Order order) { }

// Step 2: Add new recommended API
public Task ProcessAsync(Order order, CancellationToken ct = default);

// Step 3: Remove in next major version
```

---

## Extension Points

### Interface-Based Extension

```csharp
// GOOD -- interface-based extension point
public interface IWidgetValidator
{
    ValueTask<bool> ValidateAsync(Widget widget, CancellationToken ct = default);
}

// GOOD -- delegate-based extension for simple hooks
public class WidgetServiceOptions
{
    public Func<Widget, CancellationToken, ValueTask>? OnWidgetCreated { get; set; }
}
```

### Extension Method Guidelines

| Guideline | Rationale |
|-----------|-----------|
| Place extensions in the same namespace as the type | Discoverable without extra `using` statements |
| Never put extensions in `System` or `System.Linq` | Namespace pollution |
| Prefer instance methods over extensions when you own the type | Extensions are a last resort |
| Keep the `this` parameter as the most specific usable type | Avoids polluting IntelliSense |

---

## Wire Compatibility

For distributed systems, serialized data must be readable across versions.

### Requirements

| Direction | Requirement |
|-----------|-------------|
| **Backward** | Old writers → New readers |
| **Forward** | New writers → Old readers |

Both are required for zero-downtime rolling upgrades.

### Safely Evolving Wire Formats

**Phase 1: Add read-side support**

```csharp
public sealed record HeartbeatV2(
    Address From,
    long SequenceNr,
    long CreationTimeMs);  // NEW field

public object Deserialize(byte[] data, string manifest) => manifest switch
{
    "Heartbeat" => DeserializeHeartbeatV1(data),
    "HeartbeatV2" => DeserializeHeartbeatV2(data),
    _ => throw new NotSupportedException()
};
```

**Phase 2: Enable write-side (next minor version)**

```csharp
akka.cluster.use-heartbeat-v2 = on
```

### Defensive Serialization Design

```csharp
public sealed class WidgetDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("name")]
    public required string Name { get; init; }

    [JsonPropertyName("category")]
    public string? Category { get; init; }

    [JsonPropertyName("priority")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public int Priority { get; init; }
}
```

### Enum Serialization Strategy

```csharp
// GOOD -- string serialization is rename-safe
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum WidgetStatus
{
    Draft,
    Active,
    Archived
}

// RISKY -- integer serialization breaks when members are reordered
public enum WidgetPriority
{
    Low = 0,
    Medium = 1,
    High = 2
}
```

---

## API Approval Testing

Prevent accidental breaking changes with automated API surface testing.

```csharp
[Fact]
public Task ApprovePublicApi()
{
    var api = typeof(MyLibrary.PublicClass).Assembly.GeneratePublicApi();
    return Verify(api);
}
```

### PR Review Process

1. PR includes changes to `*.verified.txt` files
2. Reviewers see exact API surface changes in diff
3. Breaking changes are immediately visible
4. Conscious decision required to approve

---

## Versioning Strategy

### Semantic Versioning (Practical)

| Version | Changes Allowed |
|---------|----------------|
| **Patch** (1.0.x) | Bug fixes, security patches |
| **Minor** (1.x.0) | New features, deprecations, obsolete removal |
| **Major** (x.0.0) | Breaking changes, old API removal |

### Key Principles

1. **No surprise breaks** - Even major versions should be announced
2. **Extensions anytime** - New APIs can ship in any release
3. **Deprecate before remove** - `[Obsolete]` for at least one minor version
4. **Communicate timelines** - Users need to plan upgrades

---

## Pull Request Checklist

- [ ] **No removed public members** (use `[Obsolete]` instead)
- [ ] **No changed signatures** (add overloads instead)
- [ ] **No new required parameters** (use defaults)
- [ ] **API approval test updated** (`.verified.txt` changes reviewed)
- [ ] **Wire format changes are opt-in** (read-side first)
- [ ] **Breaking changes documented** (release notes, migration guide)

---

## Anti-Patterns

### Breaking Changes Disguised as Fixes

```csharp
// "Bug fix" that breaks users
public async Task<Order> GetOrderAsync(OrderId id)  // Was sync!
{
}

// Correct: Add new method, deprecate old
[Obsolete("Use GetOrderAsync instead")]
public Order GetOrder(OrderId id) => GetOrderAsync(id).Result;

public async Task<Order> GetOrderAsync(OrderId id) { }
```

### Silent Behavior Changes

```csharp
// Changing defaults breaks users
public void Configure(bool enableCaching = true)  // Was: false!

// Correct: New parameter with new name
public void Configure(
    bool enableCaching = false,
    bool enableNewCaching = true)
```

### Polymorphic Serialization

```csharp
// AVOID: Type names in wire format
{ "$type": "MyApp.Order, MyApp", "Id": 123 }

// PREFER: Explicit discriminators
{ "type": "order", "id": 123 }
```

---

## Agent Gotchas

1. **Do not use abbreviations in public API names** -- spell out words.
2. **Do not place CancellationToken before optional parameters** -- CA1068 enforces last.
3. **Do not return mutable collections from public APIs** -- return `IReadOnlyList<T>`.
4. **Do not change serialized property names without `[JsonPropertyName]` annotations**.
5. **Do not add required parameters to existing public methods** -- add overload or use defaults.
6. **Do not use `async void` in API surface** -- return `Task` or `ValueTask`.
7. **Do not design exception hierarchies without a base library exception**.
8. **Do not put extension methods in the `System` namespace**.

---

## Resources

- [Making Public API Changes](https://getakka.net/community/contributing/api-changes-compatibility.html)
- [Wire Format Changes](https://getakka.net/community/contributing/wire-compatibility.html)
- [Extend-Only Design](https://aaronstannard.com/extend-only-design/)
- [OSS Compatibility Standards](https://aaronstannard.com/oss-compatibility-standards/)
- [Semantic Versioning](https://semver.org/)
- [PublicApiGenerator](https://github.com/PublicApiGenerator/PublicApiGenerator)
- [Framework Design Guidelines](https://learn.microsoft.com/dotnet/standard/design-guidelines/)
- [Breaking changes reference](https://learn.microsoft.com/dotnet/core/compatibility/categories)
