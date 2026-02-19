# .NET Skills for Claude Code

A comprehensive Claude Code plugin with **167 skills** and **16 specialized agents** for professional .NET development. Combines battle-tested patterns from production systems with comprehensive coverage of the entire .NET ecosystem including C#, ASP.NET Core, Blazor, MAUI, EF Core, Native AOT, testing, security, performance optimization, CI/CD, and cloud-native applications.

## Installation

This plugin works with multiple AI coding assistants that support skills/agents.

### Claude Code (CLI)

[Official Docs](https://code.claude.com/docs/en/discover-plugins)

Run these commands inside the Claude Code CLI (the terminal app, not the VSCode extension):

```
/plugin marketplace add Aaronontheweb/dotnet-skills
/plugin install dotnet-skills
```

To update:
```
/plugin marketplace update
```

### GitHub Copilot

[Official Docs](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)

Clone or copy skills to your project or global config:

**Project-level** (recommended):
```bash
git clone https://github.com/Aaronontheweb/dotnet-skills.git /tmp/dotnet-skills
cp -r /tmp/dotnet-skills/skills/* .github/skills/
```

**Global** (all projects):
```bash
mkdir -p ~/.copilot/skills
cp -r /tmp/dotnet-skills/skills/* ~/.copilot/skills/
```

### OpenCode

[Official Docs](https://opencode.ai/docs/skills)

```bash
git clone https://github.com/Aaronontheweb/dotnet-skills.git /tmp/dotnet-skills

mkdir -p ~/.config/opencode/skills ~/.config/opencode/agents
for skill_file in /tmp/dotnet-skills/skills/*/SKILL.md; do
  skill_name=$(grep -m1 "^name:" "$skill_file" | sed 's/name: *//')
  mkdir -p ~/.config/opencode/skills/$skill_name
  cp "$skill_file" ~/.config/opencode/skills/$skill_name/SKILL.md
done
cp /tmp/dotnet-skills/agents/*.md ~/.config/opencode/agents/
```

---

## Add to AGENTS.md

Copy the following snippet into your project's `AGENTS.md` file to enable intelligent skill routing:

```markdown
## .NET Skill Library

You have access to a comprehensive .NET skill library. Use these skills for any C#/.NET development work. Always prefer skill-guided patterns over pre-training knowledge.

### Skill Routing by Task Type

**Writing C# Code:**
- `modern-csharp-coding-standards` - Records, pattern matching, immutability, value objects, async patterns
- `csharp-concurrency-patterns` - Choosing between async/await, Channels, locks, synchronization primitives
- `csharp-api-design` - API surface design, versioning, backward compatibility
- `csharp-type-design-performance` - Sealed classes, readonly structs, Span<T>, Memory<T>

**Entity Framework Core:**
- `efcore-patterns` - DbContext lifecycle, NoTracking, query splitting, migrations, interceptors
- `database-performance` - N+1 prevention, read/write separation, query optimization

**ASP.NET Core Web:**
- `middleware-patterns` - Pipeline ordering, custom middleware, exception handling
- `razor-pages-patterns` - Page models, validation, anti-forgery, routing
- `validation-patterns` - FluentValidation, DataAnnotations, custom validators
- `exception-handling` - ProblemDetails, global handlers, error responses
- `caching-strategies` - Output caching, Redis, HybridCache (.NET 9+)
- `rate-limiting` - Request throttling, sliding window, concurrency limits
- `security-headers` - CSP, HSTS, CORS, security middleware

**Background Processing:**
- `background-services` - BackgroundService, IHostedService, outbox pattern, graceful shutdown
- `dotnet-channels` - Producer/consumer, bounded channels, backpressure

**Dependency Injection:**
- `microsoft-extensions-dependency-injection` - Service lifetimes, keyed services, factory patterns
- `microsoft-extensions-configuration` - IOptions, configuration providers, secrets

**Testing:**
- `dotnet-testing-strategy` - Test pyramid, unit vs integration decisions
- `dotnet-xunit` - xUnit patterns, fixtures, theory data
- `testcontainers` - Docker-based integration tests, database fixtures
- `snapshot-testing` - Verify library, approval testing
- `dotnet-playwright` - E2E browser testing
- `crap-analysis` - CRAP scores, coverage analysis

**Performance:**
- `dotnet-benchmarkdotnet` - Benchmark design, measurement methodology
- `dotnet-performance-patterns` - Allocation reduction, GC optimization
- `dotnet-profiling` - Profiler usage, hotspot identification
- `dotnet-gc-memory` - GC modes, memory pressure, Large Object Heap

**Native AOT:**
- `dotnet-native-aot` - AOT compilation, publishing, constraints
- `dotnet-trimming` - Size optimization, linker configuration
- `dotnet-aot-wasm` - WASM AOT with Blazor

**Security:**
- `dotnet-security-owasp` - OWASP Top 10 for .NET
- `dotnet-cryptography` - Encryption, hashing, key management
- `dotnet-secrets-management` - Secret storage, Azure Key Vault, user secrets
- `asp-net-core-identity-patterns` - Authentication, authorization, MFA

**UI Frameworks:**
- `dotnet-blazor-patterns` - Server/WASM/Hybrid patterns
- `dotnet-blazor-components` - Component lifecycle, rendering
- `dotnet-maui-development` - Cross-platform mobile/desktop
- `dotnet-winui` - Windows App SDK, WinUI 3
- `razor-pages-patterns` - Server-side web UI

**CI/CD:**
- `dotnet-gha-patterns` - GitHub Actions workflow patterns
- `dotnet-gha-build-test` - Build/test matrix, caching
- `dotnet-gha-publish` - NuGet, container publishing
- `dotnet-ado-patterns` - Azure DevOps pipelines

**Architecture:**
- `dotnet-architecture-patterns` - Clean architecture, vertical slice, modular monolith
- `dotnet-solid-principles` - SOLID in practice
- `dotnet-domain-modeling` - DDD patterns, aggregates
- `project-structure` - Solution layout, Directory.Build.props

**Deployment:**
- `fly-io` - Fly.io deployment, Machines, Volumes, networking
- `dotnet-containers` - Docker for .NET
- `dotnet-container-deployment` - Container orchestration

**Specialized Frameworks:**
- `csharp-wolverinefx` - Messaging, HTTP services, Marten event sourcing
- `aspire-configuration` - .NET Aspire AppHost configuration
- `aspire-integration-testing` - Aspire testing patterns
- `signalr-integration` - Real-time communication

### Meta-Skills (Run After Changes)

- `slopwatch` - Detect LLM-generated anti-patterns
- `dotnet-agent-gotchas` - Common AI mistakes in .NET
- `dotnet-build-analysis` - Build output analysis

### Agent Activation

For complex domain-specific tasks, consider activating a specialist agent:
- `dotnet-csharp-concurrency-specialist` - Race conditions, deadlocks, thread safety
- `dotnet-security-reviewer` - Security audit, OWASP compliance
- `dotnet-performance-analyst` - Profiling, benchmarking
- `dotnet-blazor-specialist` - Blazor architecture
- `dotnet-testing-specialist` - Test strategy design
```

---

## Specialized Agents

Agents are AI personas with deep domain expertise. They're invoked automatically when Claude Code detects relevant tasks.

| Agent | Expertise |
|-------|-----------|
| **dotnet-architect** | Architecture patterns, framework choices, design patterns |
| **dotnet-csharp-concurrency-specialist** | Race conditions, deadlocks, thread safety, synchronization |
| **dotnet-security-reviewer** | OWASP compliance, secrets exposure, cryptographic misuse |
| **dotnet-blazor-specialist** | Blazor Server/WASM/Hybrid/Auto components, state, auth |
| **dotnet-uno-specialist** | Uno Platform, MVUX patterns, Toolkit controls, MCP |
| **dotnet-maui-specialist** | .NET MAUI, platform-specific development, Native AOT |
| **dotnet-performance-analyst** | Profiling data, benchmark results, GC behavior |
| **dotnet-benchmark-designer** | BenchmarkDotNet benchmarks, measurement methodology |
| **dotnet-docs-generator** | Mermaid diagrams, XML docs, GitHub-native docs |
| **dotnet-async-performance-specialist** | ValueTask correctness, ConfigureAwait, ThreadPool tuning |
| **dotnet-aspnetcore-specialist** | Middleware, DI patterns, minimal APIs, request pipeline |
| **dotnet-testing-specialist** | Test pyramids, unit vs integration, test data management |
| **dotnet-cloud-specialist** | .NET Aspire, AKS deployment, distributed tracing |
| **dotnet-code-review-agent** | Multi-dimensional code review |
| **dotnet-concurrency-specialist** | Threading, async/await, race conditions |
| **docfx-specialist** | DocFX builds, API documentation, markdown linting |

---

## Skills Library

### Core C# Language

Modern C# patterns for clean, performant code.

| Skill | Description |
|-------|-------------|
| **csharp-coding-standards** | Records, pattern matching, nullable types, value objects, naming conventions, file organization, analyzer enforcement |
| **csharp-concurrency-patterns** | Decision framework for async/await, Channels, locks, SemaphoreSlim, Interlocked, ConcurrentDictionary |
| **csharp-api-design** | API surface design, parameter ordering, return types, error reporting, versioning |
| **csharp-type-design-performance** | Sealed classes, readonly structs, Span<T>, Memory<T>, FrozenDictionary |
| **dotnet-csharp-modern-patterns** | C# 12+ features, primary constructors, collection expressions |
| **dotnet-csharp-async-patterns** | Async/await, Task, ValueTask, cancellation, ConfigureAwait |
| **dotnet-csharp-source-generators** | Source generator authoring, incremental generators |
| **dotnet-csharp-code-smells** | Anti-pattern detection and refactoring |
| **dotnet-roslyn-analyzers** | Custom analyzer development |
| **dotnet-linq-optimization** | LINQ performance, deferred execution |
| **dotnet-io-pipelines** | System.IO.Pipelines for high-performance I/O |
| **dotnet-native-interop** | P/Invoke, interop patterns |

### Architecture

Enterprise architecture patterns and practices.

| Skill | Description |
|-------|-------------|
| **dotnet-architecture-patterns** | Clean architecture, vertical slice, modular monolith |
| **dotnet-solid-principles** | SOLID in practice |
| **dotnet-domain-modeling** | DDD patterns, aggregates, domain events |
| **dotnet-messaging-patterns** | Message queues, event-driven architecture |
| **dotnet-structured-logging** | Serilog, structured logging patterns |
| **dotnet-aspire-patterns** | .NET Aspire orchestration |

### ASP.NET Core

Web application patterns.

| Skill | Description |
|-------|-------------|
| **middleware-patterns** | Pipeline ordering, custom middleware, IExceptionHandler |
| **razor-pages-patterns** | Page models, validation, anti-forgery, routing |
| **validation-patterns** | FluentValidation, DataAnnotations, IValidateOptions<T> |
| **exception-handling** | ProblemDetails, global handlers |
| **caching-strategies** | Output caching, Redis, HybridCache |
| **rate-limiting** | Request throttling, sliding window |
| **security-headers** | CSP, HSTS, CORS |
| **background-services** | BackgroundService, IHostedService, outbox, graceful shutdown |
| **signalr-integration** | Real-time communication |

### Data Access

Database patterns that scale.

| Skill | Description |
|-------|-------------|
| **efcore-patterns** | DbContext lifecycle, NoTracking, query splitting, migrations, interceptors, compiled queries |
| **database-performance** | N+1 prevention, read/write separation |
| **dotnet-data-access-strategy** | EF Core vs Dapper vs ADO.NET |

### Security

Security best practices for .NET applications.

| Skill | Description |
|-------|-------------|
| **dotnet-security-owasp** | OWASP Top 10 for .NET |
| **dotnet-secrets-management** | Secret storage, Azure Key Vault |
| **dotnet-cryptography** | Encryption, hashing, key management |
| **asp-net-core-identity-patterns** | Authentication, authorization, MFA |
| **data-protection** | ASP.NET Core Data Protection API |

### Testing

Comprehensive testing strategies.

| Skill | Description |
|-------|-------------|
| **dotnet-testing-strategy** | Test pyramid, unit vs integration |
| **dotnet-xunit** | xUnit patterns, fixtures |
| **testcontainers** | Docker-based integration tests |
| **snapshot-testing** | Verify library, custom converters, CI workflow |
| **dotnet-playwright** | E2E browser testing |
| **crap-analysis** | CRAP scores, coverage thresholds |

### Performance

Performance optimization and profiling.

| Skill | Description |
|-------|-------------|
| **dotnet-benchmarkdotnet** | Benchmark design, measurement |
| **dotnet-performance-patterns** | Allocation reduction, optimization |
| **dotnet-profiling** | Profiler usage, hotspots |
| **dotnet-gc-memory** | GC modes, LOH, memory pressure |

### Native AOT

Native AOT compilation and optimization.

| Skill | Description |
|-------|-------------|
| **dotnet-native-aot** | AOT compilation, constraints |
| **dotnet-trimming** | Size optimization, linker |
| **dotnet-aot-wasm** | WASM AOT with Blazor |

### UI Frameworks

Desktop and web UI frameworks.

| Skill | Description |
|-------|-------------|
| **dotnet-blazor-patterns** | Server/WASM/Hybrid patterns |
| **dotnet-blazor-components** | Component lifecycle, rendering |
| **dotnet-blazor-auth** | Blazor authentication |
| **dotnet-maui-development** | Cross-platform mobile/desktop |
| **dotnet-winui** | Windows App SDK, WinUI 3 |
| **dotnet-wpf-modern** | Modern WPF patterns |
| **dotnet-accessibility** | Accessibility standards |
| **bootstrap5-ui** | Bootstrap 5 integration |

### CI/CD

Continuous integration and deployment.

| Skill | Description |
|-------|-------------|
| **dotnet-gha-patterns** | GitHub Actions patterns |
| **dotnet-gha-build-test** | Build/test workflows |
| **dotnet-gha-publish** | NuGet/container publishing |
| **dotnet-ado-patterns** | Azure DevOps pipelines |

### Deployment

Deployment and infrastructure.

| Skill | Description |
|-------|-------------|
| **fly-io** | Fly.io deployment, Machines, Volumes |
| **dotnet-containers** | Docker for .NET |
| **dotnet-container-deployment** | Container orchestration |

### Specialized Frameworks

Domain-specific frameworks.

| Skill | Description |
|-------|-------------|
| **csharp-wolverinefx** | Messaging, HTTP, Marten event sourcing |
| **aspire-configuration** | .NET Aspire configuration |
| **aspire-integration-testing** | Aspire testing |

### Meta-Skills

Skills for AI assistants.

| Skill | Description |
|-------|-------------|
| **slopwatch** | LLM anti-pattern detection, CLI usage |
| **dotnet-agent-gotchas** | Common AI mistakes in .NET |
| **dotnet-build-analysis** | Build output analysis |

---

## Key Principles

These skills emphasize patterns that work in production:

- **Immutability by default** - Records, readonly structs, value objects
- **Type safety** - Nullable reference types, strongly-typed IDs
- **Composition over inheritance** - No abstract base classes, sealed by default
- **Performance-aware** - Span&lt;T&gt;, pooling, deferred enumeration
- **Testable** - DI everywhere, pure functions, explicit dependencies
- **No magic** - No AutoMapper, no reflection-heavy frameworks

---

## Repository Structure

```
dotnet-skills/
├── .claude-plugin/
│   └── plugin.json         # Plugin manifest
├── agents/                 # 16 specialized agents
└── skills/                 # 167 skills
```

---

## Acknowledgements

- Skills merged from [dotnet-artisan](https://github.com/novotnyllc/dotnet-artisan) by Claire Novotny LLC
- Original patterns from production systems

---

## Author

Created by [Aaron Stannard](https://aaronstannard.com/) ([@Aaronontheweb](https://github.com/Aaronontheweb))

## License

MIT License - Copyright (c) 2025 Aaron Stannard
