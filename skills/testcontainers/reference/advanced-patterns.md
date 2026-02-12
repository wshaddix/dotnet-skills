# Advanced Testcontainers Patterns

This reference covers advanced patterns for using Testcontainers in .NET integration tests.

## Network Configuration

### Multi-Container Networks

When you need multiple containers to communicate:

```csharp
public class MultiContainerTests : IAsyncLifetime
{
    private readonly INetwork _network;
    private readonly TestcontainersContainer _dbContainer;
    private readonly TestcontainersContainer _redisContainer;

    public MultiContainerTests()
    {
        _network = new TestcontainersNetworkBuilder()
            .Build();

        _dbContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("postgres:latest")
            .WithNetwork(_network)
            .WithNetworkAliases("db")
            .WithEnvironment("POSTGRES_PASSWORD", "postgres")
            .Build();

        _redisContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("redis:alpine")
            .WithNetwork(_network)
            .WithNetworkAliases("redis")
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _network.CreateAsync();
        await Task.WhenAll(
            _dbContainer.StartAsync(),
            _redisContainer.StartAsync());
    }

    public async Task DisposeAsync()
    {
        await Task.WhenAll(
            _dbContainer.DisposeAsync().AsTask(),
            _redisContainer.DisposeAsync().AsTask());
        await _network.DisposeAsync();
    }

    [Fact]
    public async Task Containers_CanCommunicate()
    {
        // Both containers can reach each other via network aliases
        // db -> redis://redis:6379
        // redis -> postgres://db:5432
    }
}
```

## Volume Mounts

Mount host directories or files into containers:

```csharp
public class VolumeMountTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _container;

    public VolumeMountTests()
    {
        _container = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("nginx:alpine")
            .WithBindMount("/host/path", "/container/path")
            .WithBindMount("/host/config.json", "/app/config.json")
            .WithPortBinding(80, true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}
```

### Using Temporary Directories

```csharp
public class TempDirectoryTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _container;
    private readonly string _tempDir;

    public TempDirectoryTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(_tempDir);

        // Write test files
        File.WriteAllText(Path.Combine(_tempDir, "data.json"), "{\"test\": \"data\"}");

        _container = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("alpine:latest")
            .WithBindMount(_tempDir, "/data")
            .WithCommand("cat", "/data/data.json")
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
        Directory.Delete(_tempDir, recursive: true);
    }
}
```

## Custom Wait Strategies

### Wait for HTTP Endpoint

```csharp
_container = new TestcontainersBuilder<TestcontainersContainer>()
    .WithImage("my-app:latest")
    .WithPortBinding(8080, true)
    .WithWaitStrategy(Wait.ForUnixContainer()
        .UntilHttpRequestIsSucceeded(r => r
            .ForPort(8080)
            .ForPath("/health")
            .WithMethod(HttpMethod.Get)
            .WithTimeout(TimeSpan.FromSeconds(30))))
    .Build();
```

### Wait for Log Message

```csharp
_container = new TestcontainersBuilder<TestcontainersContainer>()
    .WithImage("postgres:latest")
    .WithPortBinding(5432, true)
    .WithWaitStrategy(Wait.ForUnixContainer()
        .UntilMessageIsLogged("database system is ready to accept connections")
        .WithTimeout(TimeSpan.FromMinutes(2)))
    .Build();
```

### Wait for Custom Condition

```csharp
_container = new TestcontainersBuilder<TestcontainersContainer>()
    .WithImage("custom-service:latest")
    .WithPortBinding(8080, true)
    .WithWaitStrategy(Wait.ForUnixContainer()
        .UntilOperationIsSucceeded(async () =>
        {
            try
            {
                using var client = new HttpClient();
                var response = await client.GetAsync("http://localhost:8080/ready");
                return response.IsSuccessStatusCode;
            }
            catch
            {
                return false;
            }
        }, maxCallCount: 30))
    .Build();
```

## Cleanup Patterns

### Proper Resource Disposal

```csharp
public class ProperCleanupTests : IAsyncLifetime
{
    private TestcontainersContainer _container;
    private IDbConnection _connection;

    public async Task InitializeAsync()
    {
        _container = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("postgres:latest")
            .WithPortBinding(5432, true)
            .Build();

        await _container.StartAsync();

        var port = _container.GetMappedPublicPort(5432);
        _connection = new NpgsqlConnection($"Host=localhost;Port={port};...");
        await _connection.OpenAsync();
    }

    public async Task DisposeAsync()
    {
        // Dispose in reverse order of creation
        await _connection?.DisposeAsync();
        await _container?.DisposeAsync();
    }
}
```

### Test Collection Fixtures with Cleanup

```csharp
public class DatabaseFixture : IAsyncLifetime
{
    private readonly TestcontainersContainer _container;
    public IDbConnection Connection { get; private set; }

    public DatabaseFixture()
    {
        _container = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("SA_PASSWORD", "Your_password123")
            .WithPortBinding(1433, true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        // Setup connection
    }

    public async Task DisposeAsync()
    {
        await Connection.DisposeAsync();
        await _container.DisposeAsync();
    }
}

[CollectionDefinition("Database collection")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }
```

### Parallel Cleanup

```csharp
public async Task DisposeAsync()
{
    await Task.WhenAll(
        _dbContainer.DisposeAsync().AsTask(),
        _redisContainer.DisposeAsync().AsTask(),
        _rabbitContainer.DisposeAsync().AsTask());

    await _network.DisposeAsync();
}
```

## Performance Optimization

### Reusing Containers Across Tests

For faster test execution, reuse containers across tests in a class:

```csharp
[Collection("Database collection")]
public class FastDatabaseTests
{
    private readonly DatabaseFixture _fixture;

    public FastDatabaseTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task Test1()
    {
        // Use _fixture.Connection
        // Clean up data after test if needed
    }

    [Fact]
    public async Task Test2()
    {
        // Reuses the same container
    }
}

// Shared fixture
public class DatabaseFixture : IAsyncLifetime
{
    private readonly TestcontainersContainer _container;
    public IDbConnection Connection { get; private set; }

    public DatabaseFixture()
    {
        _container = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("SA_PASSWORD", "Your_password123")
            .WithPortBinding(1433, true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        // Setup connection
    }

    public async Task DisposeAsync()
    {
        await Connection.DisposeAsync();
        await _container.DisposeAsync();
    }
}

[CollectionDefinition("Database collection")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }
```

### Using Lightweight Images

```csharp
// Prefer Alpine images when available
_container = new TestcontainersBuilder<TestcontainersContainer>()
    .WithImage("redis:alpine")        // Smaller than redis:latest
    .WithImage("postgres:alpine")     // Smaller than postgres:latest
    .WithImage("nginx:alpine")        // Smaller than nginx:latest
    .Build();
```

### Limiting Container Resources

```csharp
_container = new TestcontainersBuilder<TestcontainersContainer>()
    .WithImage("postgres:latest")
    .WithResourceMapping(new CpuCount(2))
    .WithResourceMapping(new MemoryLimit(512 * 1024 * 1024)) // 512MB
    .Build();
```

### Parallel Test Execution

TestContainers handles port conflicts automatically, enabling parallel test execution:

```csharp
// tests can run in parallel - each gets unique ports
public class ParallelTest1 { /* uses postgres on random port */ }
public class ParallelTest2 { /* uses postgres on different random port */ }
public class ParallelTest3 { /* uses postgres on yet another random port */ }
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest # Has Docker pre-installed

    steps:
    - uses: actions/checkout@v3

    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: 9.0.x

    - name: Run Integration Tests
      run: |
        dotnet test tests/YourApp.IntegrationTests \
          --filter Category=Integration \
          --logger trx

    - name: Cleanup Containers
      if: always()
      run: docker container prune -f
```

### Azure DevOps

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UseDotNet@2
  inputs:
    version: '9.x'

- task: DockerInstaller@0
  inputs:
    dockerVersion: '24.0.0'

- task: DotNetCoreCLI@2
  inputs:
    command: 'test'
    projects: '**/*IntegrationTests.csproj'
    arguments: '--configuration Release'
```

## Common Issues and Solutions

### Issue 1: Container Startup Timeout

**Problem:** Container takes too long to start

**Solution:**
```csharp
_container = new TestcontainersBuilder<TestcontainersContainer>()
    .WithImage("postgres:latest")
    .WithWaitStrategy(Wait.ForUnixContainer()
        .UntilPortIsAvailable(5432)
        .WithTimeout(TimeSpan.FromMinutes(2)))
    .Build();
```

### Issue 2: Port Already in Use

**Problem:** Tests fail because port is already bound

**Solution:** Always use random port mapping:
```csharp
.WithPortBinding(5432, true) // true = assign random public port
```

### Issue 3: Containers Not Cleaning Up

**Problem:** Containers remain running after tests

**Solution:** Ensure proper disposal:
```csharp
public async Task DisposeAsync()
{
    await _connection?.DisposeAsync();
    await _container?.DisposeAsync();
}
```

### Issue 4: Tests Fail in CI But Pass Locally

**Problem:** CI environment doesn't have Docker

**Solution:** Ensure CI has Docker support:
```yaml
# GitHub Actions
runs-on: ubuntu-latest # Has Docker pre-installed
services:
  docker:
    image: docker:dind
```

## Performance Tips

1. **Reuse containers** - Share fixtures across tests in a collection
2. **Use Respawn** - Reset data without recreating containers
3. **Parallel execution** - TestContainers handles port conflicts automatically
4. **Use lightweight images** - Alpine versions are smaller and faster
5. **Cache images** - Docker will cache pulled images locally
6. **Limit container resources** - Set CPU/memory limits if needed:

```csharp
.WithResourceMapping(new CpuCount(2))
.WithResourceMapping(new MemoryLimit(512 * 1024 * 1024)) // 512MB
```
