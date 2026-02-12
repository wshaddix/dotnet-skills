---
name: aspire-integration-testing
description: Write integration tests using .NET Aspire's testing facilities with xUnit. Covers test fixtures, distributed application setup, endpoint discovery, and patterns for testing ASP.NET Core apps with real dependencies. Use when writing integration tests for .NET Aspire applications, testing ASP.NET Core apps with real database connections, or verifying service-to-service communication in distributed applications.
---

# Integration Testing with .NET Aspire + xUnit

## When to Use This Skill

Use this skill when:
- Writing integration tests for .NET Aspire applications
- Testing ASP.NET Core apps with real database connections
- Verifying service-to-service communication in distributed applications
- Testing with actual infrastructure (SQL Server, Redis, message queues) in containers
- Combining Playwright UI tests with Aspire-orchestrated services
- Testing microservices with proper service discovery and networking

## Core Principles

1. **Real Dependencies** - Use actual infrastructure (databases, caches) via Aspire, not mocks
2. **Dynamic Port Binding** - Let Aspire assign ports dynamically (`127.0.0.1:0`) to avoid conflicts
3. **Fixture Lifecycle** - Use `IAsyncLifetime` for proper test fixture setup and teardown
4. **Endpoint Discovery** - Never hard-code URLs; discover endpoints from Aspire at runtime
5. **Parallel Isolation** - Use xUnit collections to control test parallelization
6. **Health Checks** - Always wait for services to be healthy before running tests

## High-Level Testing Architecture

```
┌─────────────────┐                    ┌──────────────────────┐
│ xUnit test file │──uses────────────►│  AspireFixture       │
└─────────────────┘                    │  (IAsyncLifetime)    │
                                       └──────────────────────┘
                                               │
                                               │ starts
                                               ▼
                                    ┌───────────────────────────┐
                                    │  DistributedApplication   │
                                    │  (from AppHost)           │
                                    └───────────────────────────┘
                                               │ exposes
                                               ▼
                                  ┌──────────────────────────────┐
                                  │   Dynamic HTTP Endpoints     │
                                  └──────────────────────────────┘
                                               │ consumed by
                                               ▼
                                   ┌─────────────────────────┐
                                   │  HttpClient / Playwright│
                                   └─────────────────────────┘
```

## Required NuGet Packages

```xml
<ItemGroup>
  <PackageReference Include="Aspire.Hosting.Testing" Version="$(AspireVersion)" />
  <PackageReference Include="xunit" Version="*" />
  <PackageReference Include="xunit.runner.visualstudio" Version="*" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="*" />
</ItemGroup>
```

## CRITICAL: File Watcher Fix for Integration Tests

When running many integration tests that each start an IHost, the default .NET host builder enables file watchers for configuration reload. This exhausts file descriptor limits on Linux.

**Add this to your test project before any tests run:**

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

**Why this matters:** `[ModuleInitializer]` runs before any test code executes, setting the environment variable globally for all IHost instances created during tests.

## Reference Documentation

For detailed patterns and examples, see the following reference files:

- **[Test Fixtures](./reference/test-fixtures.md)** - xUnit test fixtures, test class organization, fixture lifecycle patterns, and database reset strategies
- **[Testing Patterns](./reference/testing-patterns.md)** - Testing individual services, service-to-service communication, real databases, message brokers, and Playwright UI tests
- **[Configuration Examples](./reference/configuration-examples.md)** - Resource configuration, environment variable configuration, and wait strategies

## Common Patterns Summary

| Pattern | Use Case |
|---------|----------|
| Basic Fixture | Simple HTTP endpoint testing |
| Endpoint Discovery | Avoid hard-coded URLs |
| Database Testing | Verify data access layer |
| Playwright Integration | Full UI testing with real backend |
| Configuration Override | Test-specific settings |
| Health Checks | Ensure services are ready |
| Service Communication | Test distributed system interactions |
| Message Queue Testing | Verify async messaging |

## Tricky / Non-Obvious Tips

| Problem | Solution |
|---------|----------|
| Tests timeout immediately | Call `await _app.StartAsync()` and wait for services to be healthy before running tests |
| Port conflicts between tests | Use xUnit `CollectionDefinition` to share fixtures and avoid starting multiple instances |
| Flaky tests due to timing | Implement proper health check polling instead of `Task.Delay()` |
| Can't connect to SQL Server | Ensure connection string is retrieved dynamically via `GetConnectionStringAsync()` |
| Parallel tests interfere | Use `[Collection]` attribute to run related tests sequentially |
| Aspire dashboard conflicts | Only one Aspire dashboard can run at a time; tests will reuse the same dashboard instance |

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Integration Tests

on:
  push:
    branches: [ main, dev ]
  pull_request:
    branches: [ main, dev ]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: 9.0.x

    - name: Restore dependencies
      run: dotnet restore

    - name: Build
      run: dotnet build --no-restore -c Release

    - name: Run integration tests
      run: |
        dotnet test tests/YourApp.IntegrationTests \
          --no-build \
          -c Release \
          --logger trx \
          --collect:"XPlat Code Coverage"

    - name: Publish test results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: "**/TestResults/*.trx"
```

## Best Practices

1. **Use `IAsyncLifetime`** - Ensures proper async initialization and cleanup
2. **Share fixtures via collections** - Reduces test execution time by reusing app instances
3. **Discover endpoints dynamically** - Never hard-code localhost:5000 or similar
4. **Wait for health checks** - Don't assume services are immediately ready
5. **Test with real dependencies** - Aspire makes it easy to use real SQL, Redis, etc.
6. **Clean up resources** - Always implement `DisposeAsync` properly
7. **Use meaningful test data** - Seed databases with realistic test data
8. **Test failure scenarios** - Verify error handling and resilience
9. **Keep tests isolated** - Each test should be independent and order-agnostic
10. **Monitor test execution time** - If tests are slow, consider parallelization or optimization

## Aspire CLI and MCP Integration

Aspire 13.1+ includes MCP (Model Context Protocol) integration for AI coding assistants like Claude Code. This allows AI tools to query application state, view logs, and inspect traces.

### Installing the Aspire CLI

```bash
# Install the Aspire CLI globally
dotnet tool install -g aspire.cli

# Or update existing installation
dotnet tool update -g aspire.cli
```

### Initializing MCP for Claude Code

```bash
# Navigate to your Aspire project
cd src/MyApp.AppHost

# Initialize MCP configuration (auto-detects Claude Code)
aspire mcp init
```

This creates the necessary configuration files for Claude Code to connect to your running Aspire application.

### Running with MCP Enabled

```bash
# Run your Aspire app with MCP server
aspire run

# The CLI will output the MCP endpoint URL
# Claude Code can then connect and query:
# - Resource states and health status
# - Real-time console logs
# - Distributed traces
# - Available Aspire integrations
```

### MCP Capabilities

When connected, AI assistants can:
- **Query resources** - Get resource states, endpoints, health status
- **Debug with logs** - Access real-time console output from all services
- **Investigate telemetry** - View structured logs and distributed traces
- **Execute commands** - Run resource-specific commands
- **Discover integrations** - List available Aspire hosting integrations (Redis, PostgreSQL, Azure services)

### Benefits for Development

- AI assistants can see your actual running application state
- Debugging assistance uses real telemetry data
- No need for manual log copying/pasting
- AI can help correlate distributed trace spans

For more details, see:
- [Aspire MCP Configuration](https://aspire.dev/get-started/configure-mcp/)
- [Aspire CLI Commands](https://aspire.dev/reference/cli/commands/aspire-mcp-init/)

---

## Debugging Tips

1. **Run Aspire Dashboard** - When tests fail, check the dashboard at `http://localhost:15888`
2. **Use Aspire CLI with MCP** - Let AI assistants query real application state
3. **Enable detailed logging** - Set `ASPIRE_ALLOW_UNSECURED_TRANSPORT=true` for more verbose output
4. **Check container logs** - Use `docker logs` to inspect container output
5. **Use breakpoints in fixtures** - Debug fixture initialization to catch startup issues
6. **Verify resource names** - Ensure resource names match between AppHost and tests
