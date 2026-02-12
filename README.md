# .NET Skills for Claude Code

A comprehensive Claude Code plugin with **47 skills** and **5 specialized agents** for professional .NET development. Battle-tested patterns from production systems covering C#, Akka.NET, Aspire, EF Core, ASP.NET Core, Razor Pages, Bootstrap, testing, security, and performance optimization.

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
# Clone to .github/skills/ in your project
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

# Global installation (directory names must match frontmatter 'name' field)
mkdir -p ~/.config/opencode/skills ~/.config/opencode/agents
for skill_file in /tmp/dotnet-skills/skills/*/SKILL.md; do
  skill_name=$(grep -m1 "^name:" "$skill_file" | sed 's/name: *//')
  mkdir -p ~/.config/opencode/skills/$skill_name
  cp "$skill_file" ~/.config/opencode/skills/$skill_name/SKILL.md
done
cp /tmp/dotnet-skills/agents/*.md ~/.config/opencode/agents/
```

---

## Suggested AGENTS.md / CLAUDE.md Snippets

These snippets go in your **project root** (the root directory of your codebase, next to your `.git` folder):
- Claude Code: `CLAUDE.md`
- OpenCode: `AGENTS.md`

Prerequisite: install/sync the dotnet-skills plugin in your assistant runtime (Claude Code or OpenCode) so the skill IDs below resolve.

To get consistent skill usage in downstream repos, add a small router snippet in `AGENTS.md` (OpenCode) or `CLAUDE.md` (Claude Code). These snippets tell the assistant which skills to use for common tasks.

### Readable snippet (copy/paste)

```markdown

## Updated AGENTS.md Instructions

Add or update the following section in your AGENTS.md file (e.g., under the "## .NET / C# Development – Use dotnet-skills Repository" block). This integrates the new skill into the routing, placing it in the "ASP.NET Core / .NET Aspire / Web" category for relevance.

```markdown
## .NET / C# Development – Use dotnet-skills Repository

You have access to a cloned, high-quality skill library at:  
**https://github.com/wshaddix/dotnet-skills** (cloned locally in this project)

This repo contains ~47 modular .NET/C# best-practice skills + 5 specialist agents.  
**ALWAYS prefer retrieval-led reasoning** over your pretraining for any .NET, C#, ASP.NET Core, EF Core, Akka.NET, Aspire, testing, performance, or concurrency work.

### Core Workflow (Mandatory)
1. When the task involves writing, reviewing, refactoring, or advising on .NET/C# code:  
   → **First**, skim the current repo patterns/files/structure.  
   → **Then**, consult the dotnet-skills library by invoking specific skill names (see routing below).  
   → Apply **only** the relevant skill(s) — load their content via path if your framework supports it (e.g., .claude/skills/... or manual copy-paste in context).  
   → Implement the **smallest effective change** that follows the skill.  
   → Note any conflicts between repo code and skill guidance → suggest fixes or ask for clarification.

### Skill Routing (Invoke by Exact Name)
Use these categories to quickly route to the right skills:

- **C# Language & Code Quality**  
  modern-csharp-coding-standards  
  csharp-concurrency-patterns  
  api-design  
  type-design-performance  

- **ASP.NET Core / Razor Pages / Web**
  razor-pages-patterns          → Production Razor Pages patterns (lifecycle, binding, validation, security)
  caching-strategies            → Output caching, memory cache, Redis, HybridCache (.NET 9+)
  logging-observability         → Serilog, correlation IDs, health checks, OpenTelemetry
  validation-patterns           → FluentValidation, data annotations, custom validators
  exception-handling            → Global exception handler, ProblemDetails, custom exceptions
  security-headers              → CSP, HSTS, security middleware
  middleware-patterns           → Custom middleware, pipeline ordering, branching
  background-services           → Hosted services, outbox pattern, graceful shutdown
  http-client-resilience        → IHttpClientFactory, Polly retry/circuit breaker
  rate-limiting                 → Request throttling, IP/user-based limits
  localization-globalization    → Multi-language support, resource files, culture formatting
  file-handling                 → File uploads, streaming, storage abstractions
  data-protection               → ASP.NET Core Data Protection, key management
  signalr-integration           → Real-time communication for Razor Pages
  feature-flags                 → Microsoft.FeatureManagement, gradual rollouts
  asp-net-core-identity-patterns → Production-grade Identity patterns (auth, roles, security)
  bootstrap5-ui                 → Bootstrap 5.3 responsive UI, grid, components, Razor integration

- **Data Access (EF Core, etc.)**  
  efcore-patterns  
  database-performance  

- **Dependency Injection & Configuration**  
  dependency-injection-patterns  
  microsoft-extensions-configuration  

- **Testing**  
  testcontainers-integration-tests  
  playwright-blazor-testing  
  snapshot-testing  
  verify-email-snapshots  
  playwright-ci-caching  
  dotnet-tunit-testing

- **Akka.NET**  
  akka-net-best-practices  
  akka-net-testing-patterns  
  akka-hosting-actor-patterns  
  akka-net-aspire-configuration  
  akka-net-management  

- **.NET Aspire**  
  aspire-configuration            → AppHost config, environment variables, portable configuration  
  aspire-integration-testing      → DistributedApplicationTestingBuilder, Aspire.Hosting.Testing  
  aspire-service-defaults         → OpenTelemetry, health checks, resilience, service discovery  
  aspire-mailpit-integration      → Email testing with Mailpit container, SMTP config  

- **General .NET Ecosystem**  
  dotnet-project-structure  
  dotnet-local-tools  
  package-management  
  serialization  

- **Quality Gates (Run these after major changes)**  
  dotnet-slopwatch          → Detects LLM-generated anti-patterns / slop  
  crap-analysis             → CRAP score & coverage analysis  

Full list of all 47 skills is in the repo's `skills/` folder — each is a self-contained SKILL.md with examples, rationale, and anti-patterns.

### Specialist Agents (Activate When Relevant)
If the task deeply matches one of these domains, switch persona / load the corresponding agent file from `agents/`:
- akka-net-specialist  
- dotnet-concurrency-specialist  
- dotnet-performance-analyst  
- dotnet-benchmark-designer  
- docfx-specialist  

Example: "Activating dotnet-concurrency-specialist persona for this threading issue."

### Integration Notes
- Skills live in: `skills/<skill-name>/SKILL.md` (e.g., `skills/modern-csharp-coding-standards/SKILL.md`)  
- If your agent framework (Claude, Cursor, OpenCode, etc.) supports skill folders or .claude-plugin, point it to the cloned repo's `.claude-plugin/plugin.json` for auto-discovery.  
- For manual workflows: explicitly reference skill paths in your thinking trace, e.g., "Loading guidance from skills/csharp-concurrency-patterns/SKILL.md"  
- Core principles from the repo (always apply): immutability by default, type safety (nullable + strong IDs), composition > inheritance, performance-aware (Span<T>, pooling), testable code, no heavy magic (avoid AutoMapper/reflection abuse).

Do NOT freestyle .NET advice — route through dotnet-skills first to stay consistent with production-grade patterns.
```


## Specialized Agents

Agents are AI personas with deep domain expertise. They're invoked automatically when Claude Code detects relevant tasks.

| Agent                             | Expertise                                                              |
| --------------------------------- | ---------------------------------------------------------------------- |
| **akka-net-specialist**           | Actor systems, clustering, persistence, Akka.Streams, message patterns |
| **dotnet-concurrency-specialist** | Threading, async/await, race conditions, deadlock analysis             |
| **dotnet-benchmark-designer**     | BenchmarkDotNet setup, custom benchmarks, measurement strategies       |
| **dotnet-performance-analyst**    | Profiler analysis, benchmark interpretation, regression detection      |
| **docfx-specialist**              | DocFX builds, API documentation, markdown linting                      |

---

## Skills Library

### Akka.NET

Production patterns for building distributed systems with Akka.NET.

| Skill                      | What You'll Learn                                                           |
| -------------------------- | --------------------------------------------------------------------------- |
| **best-practices**         | EventStream vs DistributedPubSub, supervision strategies, actor hierarchies |
| **testing-patterns**       | Akka.Hosting.TestKit, async assertions, TestProbe patterns                  |
| **hosting-actor-patterns** | Props factories, `IRequiredActor<T>`, DI scope management in actors         |
| **aspire-configuration**   | Akka.NET + .NET Aspire integration, HOCON with IConfiguration               |
| **management**             | Akka.Management, health checks, cluster bootstrap                           |

### C# Language

Modern C# patterns for clean, performant code.

| Skill                       | What You'll Learn                                                       |
| --------------------------- | ----------------------------------------------------------------------- |
| **coding-standards**        | Records, pattern matching, nullable types, value objects, no AutoMapper |
| **concurrency-patterns**    | When to use Task vs Channel vs lock vs actors                           |
| **api-design**              | Extend-only design, API/wire compatibility, versioning strategies       |
| **type-design-performance** | Sealed classes, readonly structs, static pure functions, Span&lt;T&gt;  |

### ASP.NET Core & Razor Pages

Production patterns for web applications.

| Skill | What You'll Learn |
| ----- | ----------------- |
| **razor-pages-patterns** | Best practices for building production-grade ASP.NET Core Razor Pages applications. Focuses on structure, lifecycle, binding, validation, security, and maintainability in web apps using Razor Pages as the primary UI framework.|
| **mjml-email-templates** | MJML syntax, responsive layouts, template renderer, composer pattern |
| **caching-strategies** | Output caching, memory cache, Redis distributed cache, HybridCache (.NET 9+), cache invalidation strategies |
| **logging-observability** | Structured logging with Serilog, correlation IDs, health checks, OpenTelemetry integration, LoggerMessage pattern |
| **validation-patterns** | FluentValidation integration, MediatR pipeline behaviors, data annotations, custom validators, string trimming |
| **exception-handling** | Global exception handler, ProblemDetails API, custom exceptions, error pages, status code handling |
| **security-headers** | CSP configuration, HSTS, security headers middleware, nonce-based inline scripts, violation reporting |
| **middleware-patterns** | Custom middleware, conditional middleware, pipeline ordering, branching, factory pattern |
| **background-services** | Hosted services, background jobs, outbox pattern, graceful shutdown handling |
| **http-client-resilience** | IHttpClientFactory, Polly retry/circuit breaker, timeout handling, resilience strategies |
| **localization-globalization** | Multi-language support, resource files, culture switching, currency/date formatting |
| **feature-flags** | Microsoft.FeatureManagement, feature gates, gradual rollouts, Razor Page integration |
| **file-handling** | File uploads, streaming, storage abstractions, virus scanning, CDN integration |
| **data-protection** | ASP.NET Core Data Protection API, key management, database persistence, encryption |
| **signalr-integration** | Real-time communication, hub authorization, Razor Page integration |
| **rate-limiting** | Request throttling, IP/user-based limits, sliding window algorithms |
| **asp-net-core-identity-patterns** | Production-grade Identity patterns, authentication, authorization, security hardening |
| **bootstrap5-ui** | Bootstrap 5.3 responsive UI patterns, grid system, components, forms, color modes, utility classes, ASP.NET Core Razor integration |

### Data Access

Database patterns that scale.

| Skill                    | What You'll Learn                                               |
| ------------------------ | --------------------------------------------------------------- |
| **efcore-patterns**      | Entity configuration, migrations, query optimization            |
| **database-performance** | Read/write separation, N+1 prevention, AsNoTracking, row limits |

### .NET Aspire

Cloud-native application orchestration.

| Skill                   | What You'll Learn                                            |
| ----------------------- | ------------------------------------------------------------ |
| **configuration**       | AppHost config, environment variables, portable configuration outside Aspire |
| **integration-testing** | DistributedApplicationTestingBuilder, Aspire.Hosting.Testing |
| **service-defaults**    | OpenTelemetry, health checks, resilience, service discovery  |
| **mailpit-integration** | Email testing with Mailpit container, SMTP config, test assertions |

### .NET Ecosystem

Core .NET development practices.

| Skill                  | What You'll Learn                                                      |
| ---------------------- | ---------------------------------------------------------------------- |
| **project-structure**  | Solution layout, Directory.Build.props, layered architecture           |
| **package-management** | Central Package Management (CPM), shared version variables, dotnet CLI |
| **serialization**      | Protobuf, MessagePack, System.Text.Json source generators, AOT         |
| **local-tools**        | dotnet tool manifests, team-shared tooling                             |
| **slopwatch**          | Detect LLM-generated anti-patterns in your codebase                    |

### Microsoft.Extensions

Dependency injection and configuration patterns.

| Skill                    | What You'll Learn                                                 |
| ------------------------ | ----------------------------------------------------------------- |
| **configuration**        | IOptions pattern, environment-specific config, secrets management |
| **dependency-injection** | IServiceCollection extensions, scope management, keyed services   |

### Testing

Comprehensive testing strategies.

| Skill                      | What You'll Learn                                             |
| -------------------------- | ------------------------------------------------------------- |
| **testcontainers**         | Docker-based integration tests, PostgreSQL, Redis, RabbitMQ   |
| **playwright-blazor**      | E2E testing for Blazor apps, page objects, async assertions   |
| **crap-analysis**          | CRAP scores, coverage thresholds, ReportGenerator integration |
| **snapshot-testing**       | Verify library, approval testing, API response validation     |
| **verify-email-snapshots** | Snapshot test email templates, catch rendering regressions    |
| **playwright-ci-caching**  | CI/CD pipeline caching for Playwright browsers, GitHub Actions/Azure DevOps |
| **tunit-testing**          | TUnit framework setup, assertions, async testing, migration from other frameworks |

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
├── agents/                 # 5 specialized agents
│   ├── akka-net-specialist.md
│   ├── docfx-specialist.md
│   ├── dotnet-benchmark-designer.md
│   ├── dotnet-concurrency-specialist.md
│   └── dotnet-performance-analyst.md
└── skills/                 # Flat structure (47 skills)
    ├── akka-best-practices/SKILL.md
    ├── akka-hosting-actor-patterns/SKILL.md
    ├── akka-net-aspire-configuration/SKILL.md
    ├── aspire-configuration/SKILL.md
    ├── aspire-integration-testing/SKILL.md
    ├── bootstrap5-ui/SKILL.md
    ├── csharp-concurrency-patterns/SKILL.md
    ├── testcontainers-integration-tests/SKILL.md
    ├── razor-pages-patterns/SKILL.md
    ├── caching-strategies/SKILL.md
    ├── logging-observability/SKILL.md
    ├── validation-patterns/SKILL.md
    ├── exception-handling/SKILL.md
    ├── security-headers/SKILL.md
    └── ...                 # (prefixed by category)
```

---

## Contributing

Want to add a skill or agent? PRs welcome!

1. Create `skills/<skill-name>/SKILL.md` (use prefixes like `akka-`, `aspire-`, `csharp-` for category)
2. Add the path to `.claude-plugin/plugin.json`
3. Submit a PR

Skills should be comprehensive reference documents (10-40KB) with concrete examples and anti-patterns.

---

## Author

Created by [Aaron Stannard](https://aaronstannard.com/) ([@Aaronontheweb](https://github.com/Aaronontheweb))

Patterns drawn from production systems including [Akka.NET](https://getakka.net/), [Petabridge](https://petabridge.com/), and [Sdkbin](https://sdkbin.com/).

## License

MIT License - Copyright (c) 2025 Aaron Stannard

See [LICENSE](LICENSE) for full details.
