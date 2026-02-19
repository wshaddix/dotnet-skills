---
name: serialization
description: JSON and binary serialization patterns for .NET applications, including System.Text.Json source generators, Protocol Buffers, MessagePack, and AOT-compatible best practices. Use when configuring JSON serialization, choosing between formats, implementing Protocol Buffers for high-performance scenarios, or working with Native AOT.
---

# Serialization in .NET

## When to Use This Skill

Use this skill when:
- Choosing a serialization format for APIs, messaging, or persistence
- Migrating from Newtonsoft.Json to System.Text.Json
- Implementing AOT-compatible serialization
- Designing wire formats for distributed systems
- Optimizing serialization performance

---

## Serialization Format Comparison

| Format | Library | AOT-Safe | Human-Readable | Relative Size | Relative Speed | Best For |
|--------|---------|----------|----------------|---------------|----------------|----------|
| JSON | System.Text.Json (source gen) | Yes | Yes | Largest | Good | APIs, config, web clients |
| Protobuf | Google.Protobuf | Yes | No | Smallest | Fastest | Service-to-service, gRPC wire format |
| MessagePack | MessagePack-CSharp | Yes (with AOT resolver) | No | Small | Fast | High-throughput caching, real-time |
| JSON | Newtonsoft.Json | **No** (reflection) | Yes | Largest | Slower | **Legacy only -- do not use for AOT** |

### When to Choose What

- **System.Text.Json with source generators**: Default choice for APIs, configuration, and any scenario where human-readable output or web client consumption matters. AOT-safe.
- **Protobuf**: Default wire format for gRPC. Best throughput and smallest payload size for service-to-service communication. Schema-first development with `.proto` files.
- **MessagePack**: When you need binary compactness without `.proto` schema management. Good for caching layers, real-time messaging, and high-throughput scenarios.

---

## Schema-Based vs Reflection-Based

| Aspect | Schema-Based | Reflection-Based |
|--------|--------------|------------------|
| **Examples** | Protobuf, MessagePack, System.Text.Json (source gen) | Newtonsoft.Json, BinaryFormatter |
| **Type info in payload** | No (external schema) | Yes (type names embedded) |
| **Versioning** | Explicit field numbers/names | Implicit (type structure) |
| **Performance** | Fast (no reflection) | Slower (runtime reflection) |
| **AOT compatible** | Yes | No |
| **Wire compatibility** | Excellent | Poor |

**Recommendation**: Use schema-based serialization for anything that crosses process boundaries.

### Formats to Avoid

| Format | Problem |
|--------|---------|
| **BinaryFormatter** | Security vulnerabilities, deprecated, never use |
| **Newtonsoft.Json default** | Type names in payload break on rename |
| **DataContractSerializer** | Complex, poor versioning |
| **XML** | Verbose, slow, complex |

---

## System.Text.Json with Source Generators

For JSON serialization, use System.Text.Json with source generators for AOT compatibility and performance.

### Basic Setup

```csharp
using System.Text.Json.Serialization;

[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
[JsonSerializable(typeof(OrderStatus))]
public partial class AppJsonContext : JsonSerializerContext
{
}
```

### Using the Generated Context

```csharp
// Serialize
string json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);

// Deserialize
Order? result = JsonSerializer.Deserialize(json, AppJsonContext.Default.Order);

// With options
var options = new JsonSerializerOptions
{
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    TypeInfoResolver = AppJsonContext.Default
};

string json = JsonSerializer.Serialize(order, options);
```

### ASP.NET Core Integration

```csharp
var builder = WebApplication.CreateBuilder(args);

// Minimal APIs
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

// MVC Controllers
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
    });
```

### Combining Multiple Contexts

```csharp
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolver = JsonTypeInfoResolver.Combine(
        AppJsonContext.Default,
        CatalogJsonContext.Default,
        InventoryJsonContext.Default
    );
});
```

### Common Configuration

```csharp
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    WriteIndented = false)]
[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
public partial class AppJsonContext : JsonSerializerContext
{
}
```

### Handling Polymorphism

```csharp
[JsonDerivedType(typeof(CreditCardPayment), "credit_card")]
[JsonDerivedType(typeof(BankTransferPayment), "bank_transfer")]
[JsonDerivedType(typeof(WalletPayment), "wallet")]
public abstract class Payment
{
    public decimal Amount { get; init; }
    public string Currency { get; init; } = "USD";
}

public class CreditCardPayment : Payment
{
    public string Last4Digits { get; init; } = "";
}

[JsonSerializable(typeof(Payment))]
public partial class AppJsonContext : JsonSerializerContext
{
}
```

---

## Protocol Buffers (Protobuf)

Best for: Actor systems, gRPC, event sourcing, any long-lived wire format.

### Packages

```xml
<PackageReference Include="Google.Protobuf" Version="3.*" />
<PackageReference Include="Grpc.Tools" Version="2.*" PrivateAssets="All" />
```

### Proto File

```protobuf
syntax = "proto3";

import "google/protobuf/timestamp.proto";

option csharp_namespace = "MyApp.Contracts";

message OrderMessage {
  int32 id = 1;
  string customer_id = 2;
  repeated OrderItemMessage items = 3;
  google.protobuf.Timestamp created_at = 4;
}

message OrderItemMessage {
  string product_id = 1;
  int32 quantity = 2;
  double unit_price = 3;
}
```

### Standalone Protobuf (Without gRPC)

```csharp
using Google.Protobuf;

// Serialize to bytes
byte[] bytes = order.ToByteArray();

// Deserialize from bytes
var restored = OrderMessage.Parser.ParseFrom(bytes);

// Serialize to stream
using var stream = File.OpenWrite("order.bin");
order.WriteTo(stream);
```

### Proto File Registration in .csproj

```xml
<ItemGroup>
  <Protobuf Include="Protos\*.proto" GrpcServices="Both" />
</ItemGroup>
```

### Versioning Rules

```protobuf
// SAFE: Add new fields with new numbers
message Order {
  string id = 1;
  string customer_id = 2;
  string shipping_address = 5;  // NEW - safe
}

// SAFE: Remove fields (keep the number reserved)
message Order {
  string id = 1;
  reserved 2;  // customer_id removed
}

// UNSAFE: Change field types
message Order {
  int32 id = 1;  // Was: string - BREAKS!
}

// UNSAFE: Reuse field numbers
message Order {
  reserved 2;
  string new_field = 2;  // Reusing 2 - BREAKS!
}
```

---

## MessagePack

Best for: High-performance scenarios, compact payloads, actor messaging.

### Packages

```xml
<PackageReference Include="MessagePack" Version="3.*" />
<PackageReference Include="MessagePack.SourceGenerator" Version="3.*" />
```

### Basic Usage with Source Generator (AOT-Safe)

```csharp
using MessagePack;

[MessagePackObject]
public partial class Order
{
    [Key(0)]
    public int Id { get; init; }

    [Key(1)]
    public string CustomerId { get; init; } = "";

    [Key(2)]
    public List<OrderItem> Items { get; init; } = [];

    [Key(3)]
    public DateTimeOffset CreatedAt { get; init; }

    [Key(4)]
    public string? Notes { get; init; }
}
```

### Serialization

```csharp
// Serialize
byte[] bytes = MessagePackSerializer.Serialize(order);

// Deserialize
var restored = MessagePackSerializer.Deserialize<Order>(bytes);

// With compression (LZ4)
var lz4Options = MessagePackSerializerOptions.Standard.WithCompression(
    MessagePackCompression.Lz4BlockArray);
byte[] compressed = MessagePackSerializer.Serialize(order, lz4Options);
```

### AOT Resolver Setup

```csharp
MessagePackSerializer.DefaultOptions = MessagePackSerializerOptions.Standard
    .WithResolver(GeneratedResolver.Instance);
```

---

## Wire Compatibility Patterns

### Tolerant Reader

Old code must safely ignore unknown fields:

```csharp
// Protobuf/MessagePack: Automatic - unknown fields skipped
// System.Text.Json: Configure to allow
var options = new JsonSerializerOptions
{
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip
};
```

### Introduce Read Before Write

Deploy deserializers before serializers for new formats:

```csharp
// Phase 1: Add deserializer (deployed everywhere)
public Order Deserialize(byte[] data, string manifest) => manifest switch
{
    "Order.V1" => DeserializeV1(data),
    "Order.V2" => DeserializeV2(data),  // NEW - can read V2
    _ => throw new NotSupportedException()
};

// Phase 2: Enable serializer (after V1 deployed everywhere)
public (byte[] data, string manifest) Serialize(Order order) =>
    _useV2Format
        ? (SerializeV2(order), "Order.V2")
        : (SerializeV1(order), "Order.V1");
```

### Never Embed Type Names

```csharp
// BAD: Type name in payload - renaming class breaks wire format
{
    "$type": "MyApp.Order, MyApp",
    "id": 123
}

// GOOD: Explicit discriminator - refactoring safe
{
    "type": "order",
    "id": 123
}
```

---

## Performance Comparison

Approximate throughput (higher is better):

| Format | Serialize | Deserialize | Size |
|--------|-----------|-------------|------|
| MessagePack | ★★★★★ | ★★★★★ | ★★★★★ |
| Protobuf | ★★★★★ | ★★★★★ | ★★★★★ |
| System.Text.Json (source gen) | ★★★★☆ | ★★★★☆ | ★★★☆☆ |
| System.Text.Json (reflection) | ★★★☆☆ | ★★★☆☆ | ★★★☆☆ |
| Newtonsoft.Json | ★★☆☆☆ | ★★☆☆☆ | ★★★☆☆ |

### Optimization Tips

- **Reuse `JsonSerializerOptions`** -- creating options is expensive
- **Use `JsonSerializerContext`** -- eliminates warm-up cost
- **Use `Utf8JsonWriter` / `Utf8JsonReader`** for streaming scenarios
- **Use Protobuf `ByteString`** for binary data instead of base64-encoded strings
- **Enable MessagePack LZ4 compression** for large payloads

---

## Anti-Patterns: Reflection-Based Serialization

**Do not use reflection-based serializers in Native AOT or trimming scenarios.**

### Newtonsoft.Json (JsonConvert)

```csharp
// BAD: Reflection-based -- fails under AOT/trimming
var json = JsonConvert.SerializeObject(order);
var order = JsonConvert.DeserializeObject<Order>(json);

// GOOD: Source-generated -- AOT-safe
var json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);
var order = JsonSerializer.Deserialize(json, AppJsonContext.Default.Order);
```

### System.Text.Json Without Source Generators

```csharp
// BAD: No context -- uses runtime reflection
var json = JsonSerializer.Serialize(order);

// GOOD: Explicit context -- uses source-generated code
var json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);
```

### Migration Path from Newtonsoft.Json

1. Replace `JsonConvert.SerializeObject` / `DeserializeObject` with `JsonSerializer.Serialize` / `Deserialize`
2. Replace `[JsonProperty]` with `[JsonPropertyName]`
3. Replace `JsonConverter` base class with `JsonConverter<T>` from System.Text.Json
4. Create a `JsonSerializerContext` with `[JsonSerializable]` for all serialized types
5. Replace `JObject` / `JToken` dynamic access with `JsonDocument` / `JsonElement` or strongly-typed models
6. Test serialization round-trips -- attribute semantics differ

---

## Akka.NET Serialization

For Akka.NET actor systems, use schema-based serialization:

```hocon
akka {
  actor {
    serializers {
      messagepack = "Akka.Serialization.MessagePackSerializer, Akka.Serialization.MessagePack"
    }
    serialization-bindings {
      "MyApp.Messages.IMessage, MyApp" = messagepack
    }
  }
}
```

---

## Key Principles

- **Default to System.Text.Json with source generators** for all JSON serialization
- **Use Protobuf for service-to-service binary serialization**
- **Use MessagePack for high-throughput caching and real-time**
- **Never use Newtonsoft.Json for new AOT-targeted projects**
- **Always register `JsonSerializerContext` in ASP.NET Core**
- **Annotate all serialized types** -- source generators only generate code for listed types

---

## Agent Gotchas

1. **Do not use `JsonSerializer.Serialize(obj)` without a context in AOT projects** -- it falls back to reflection.
2. **Do not forget to list collection types in `[JsonSerializable]`** -- `[JsonSerializable(typeof(Order))]` does not cover `List<Order>`.
3. **Do not use Newtonsoft.Json `[JsonProperty]` attributes with System.Text.Json** -- they are silently ignored.
4. **Do not mix MessagePack `[Key]` integer keys with `[Key]` string keys** in the same type hierarchy.
5. **Do not omit `GrpcServices` attribute on `<Protobuf>` items** -- without it, both client and server stubs are generated.

---

## Resources

- **System.Text.Json Source Generation**: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation
- **Migrate from Newtonsoft.Json to System.Text.Json**: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/migrate-from-newtonsoft
- **Protocol Buffers**: https://protobuf.dev/
- **MessagePack-CSharp**: https://github.com/MessagePack-CSharp/MessagePack-CSharp
- **Akka.NET Serialization**: https://getakka.net/articles/networking/serialization.html
- **Wire Compatibility**: https://getakka.net/community/contributing/wire-compatibility.html
- **Native AOT deployment**: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/
