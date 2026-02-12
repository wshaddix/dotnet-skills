---
name: akka-net-testing-patterns
description: Write unit and integration tests for Akka.NET actors using modern Akka.Hosting.TestKit patterns. Covers dependency injection, TestProbes, persistence testing, and actor interaction verification. Use when writing unit tests for Akka.NET actors, testing persistent actors with event sourcing, verifying actor interactions and message flows, or testing cluster sharding behavior locally.
---

# Akka.NET Testing Patterns

## When to Use This Skill

Use this skill when:
- Writing unit tests for Akka.NET actors
- Testing persistent actors with event sourcing
- Verifying actor interactions and message flows
- Testing actor supervision and lifecycle
- Mocking external dependencies in actor tests
- Testing cluster sharding behavior locally
- Verifying actor state recovery and persistence

## Choosing Your Testing Approach

### ✅ Use Akka.Hosting.TestKit (Recommended for 95% of Use Cases)

**When:**
- Building modern .NET applications with `Microsoft.Extensions.DependencyInjection`
- Using Akka.Hosting for actor configuration in production
- Need to inject services into actors (`IOptions`, `DbContext`, `ILogger`, HTTP clients, etc.)
- Testing applications that use ASP.NET Core, Worker Services, or .NET Aspire
- Working with modern Akka.NET projects (Akka.NET v1.5+)

**Advantages:**
- Native dependency injection support - override services with fakes in tests
- Configuration parity with production (same extension methods work in tests)
- Clean separation between actor logic and infrastructure
- Better integration with .NET ecosystem
- Type-safe actor registry for retrieving actors
- Supports both local and clustered testing modes

**This guide focuses primarily on Akka.Hosting.TestKit patterns.**

### ⚠️ Use Traditional Akka.TestKit

**When:**
- Contributing to Akka.NET core library development
- Working in environments without `Microsoft.Extensions` (console apps, legacy systems)
- Legacy codebases using manual `Props` creation without DI
- Need direct control over low-level ActorSystem configuration
- Working with Akka.NET projects pre-v1.5

**Note:** If starting a new project in 2025+, strongly prefer Akka.Hosting.TestKit unless you have specific constraints.

Traditional TestKit patterns are covered briefly at the end of this document.

---

## Core Principles (Akka.Hosting.TestKit)

1. **Inherit from `Akka.Hosting.TestKit.TestKit`** - This is a framework base class, not a user-defined one
2. **Override `ConfigureServices()`** - Replace real services with fakes/mocks
3. **Override `ConfigureAkka()`** - Configure actors using the same extension methods as production
4. **Use `ActorRegistry`** - Type-safe retrieval of actor references
5. **Composition over Inheritance** - Fake services as fields, not base classes
6. **No Custom Base Classes** - Use method overrides, not inheritance hierarchies
7. **Test One Actor at a Time** - Use TestProbes for dependencies
8. **Match Production Patterns** - Same extension methods, different `AkkaExecutionMode`

---

## Required NuGet Packages

```xml
<ItemGroup>
  <!-- Core testing framework -->
  <PackageReference Include="Akka.Hosting.TestKit" Version="*" />

  <!-- xUnit (or your preferred test framework) -->
  <PackageReference Include="xunit" Version="*" />
  <PackageReference Include="xunit.runner.visualstudio" Version="*" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="*" />

  <!-- Assertions (recommended) -->
  <PackageReference Include="FluentAssertions" Version="*" />

  <!-- In-memory persistence for testing -->
  <PackageReference Include="Akka.Persistence.Hosting" Version="*" />

  <!-- If testing cluster sharding -->
  <PackageReference Include="Akka.Cluster.Hosting" Version="*" />
</ItemGroup>
```

---

## CRITICAL: File Watcher Fix for Test Projects

Akka.Hosting.TestKit spins up real `IHost` instances, which by default enable file watchers for configuration reload. When running many tests, this exhausts file descriptor limits on Linux (inotify watch limit).

**Add this to your test project - it runs before any tests execute:**

```csharp
// TestEnvironmentInitializer.cs
using System.Runtime.CompilerServices;

namespace YourApp.Tests;

internal static class TestEnvironmentInitializer
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        // Disable config file watching in test hosts
        // Prevents file descriptor exhaustion (inotify watch limit) on Linux
        Environment.SetEnvironmentVariable("DOTNET_HOSTBUILDER__RELOADCONFIGONCHANGE", "false");
    }
}
```

**Why this matters:**
- `[ModuleInitializer]` runs automatically before any test code
- Sets the environment variable globally for all `IHost` instances
- Prevents cryptic `inotify` errors when running 100+ tests
- Also applies to Aspire integration tests that use `IHost`

---

## Reference Materials

For detailed testing patterns and examples, see:

- **[TestKit Patterns](reference/testkit-patterns.md)** - Basic actor tests, TestProbes, auto-responders, persistent actor testing, and configuration extension methods
- **[Advanced Testing Patterns](reference/advanced-testing.md)** - Cluster sharding tests, async behavior testing, scenario-based integration tests, and Akka.Reminders
- **[Troubleshooting Guide](reference/troubleshooting.md)** - Common patterns summary, anti-patterns to avoid, debugging tips, and CI/CD integration
