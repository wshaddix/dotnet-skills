---
name: testcontainers
description: Patterns for using Testcontainers in .NET integration tests to spin up real dependencies like databases and message queues. Use when writing integration tests that require real databases, testing with message brokers like RabbitMQ or Kafka, or isolating test dependencies with Docker containers.
---

# Integration Testing with TestContainers

## When to Use This Skill

Use this skill when:
- Writing integration tests that need real infrastructure (databases, caches, message queues)
- Testing data access layers against actual databases
- Verifying message queue integrations
- Testing Redis caching behavior
- Avoiding mocks for infrastructure components
- Ensuring tests work against production-like environments
- Testing database migrations and schema changes

## Core Principles

1. **Real Infrastructure Over Mocks** - Use actual databases/services in containers, not mocks
2. **Test Isolation** - Each test gets fresh containers or fresh data
3. **Automatic Cleanup** - TestContainers handles container lifecycle and cleanup
4. **Fast Startup** - Reuse containers across tests in the same class when appropriate
5. **CI/CD Compatible** - Works seamlessly in Docker-enabled CI environments
6. **Port Randomization** - Containers use random ports to avoid conflicts

## Why TestContainers Over Mocks?

### Problems with Mocking Infrastructure

```csharp
// BAD: Mocking a database
public class OrderRepositoryTests
{
    private readonly Mock<IDbConnection> _mockDb = new();

    [Fact]
    public async Task GetOrder_ReturnsOrder()
    {
        // This doesn't test real SQL behavior, constraints, or performance
        _mockDb.Setup(db => db.QueryAsync<Order>(It.IsAny<string>()))
            .ReturnsAsync(new[] { new Order { Id = 1 } });

        var repo = new OrderRepository(_mockDb.Object);
        var order = await repo.GetOrderAsync(1);

        Assert.NotNull(order);
    }
}
```

Problems:
- Doesn't test actual SQL queries
- Misses database constraints, indexes, and performance
- Can give false confidence
- Doesn't catch SQL syntax errors or schema mismatches

### Better: TestContainers with Real Database

```csharp
// GOOD: Testing against a real database
public class OrderRepositoryTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _dbContainer;
    private IDbConnection _connection;

    public OrderRepositoryTests()
    {
        _dbContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("SA_PASSWORD", "Your_password123")
            .WithPortBinding(1433, true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _dbContainer.StartAsync();

        var port = _dbContainer.GetMappedPublicPort(1433);
        var connectionString = $"Server=localhost,{port};Database=TestDb;User Id=sa;Password=Your_password123;TrustServerCertificate=true";

        _connection = new SqlConnection(connectionString);
        await _connection.OpenAsync();

        // Run migrations
        await RunMigrationsAsync(_connection);
    }

    public async Task DisposeAsync()
    {
        await _connection.DisposeAsync();
        await _dbContainer.DisposeAsync();
    }

    [Fact]
    public async Task GetOrder_WithRealDatabase_ReturnsOrder()
    {
        // Arrange: Insert real test data
        await _connection.ExecuteAsync(
            "INSERT INTO Orders (Id, CustomerId, Total) VALUES (1, 'CUST1', 100.00)");

        var repo = new OrderRepository(_connection);

        // Act: Execute against real database
        var order = await repo.GetOrderAsync(1);

        // Assert: Verify actual database behavior
        Assert.NotNull(order);
        Assert.Equal(1, order.Id);
        Assert.Equal("CUST1", order.CustomerId);
        Assert.Equal(100.00m, order.Total);
    }
}
```

Benefits:
- Tests real SQL queries and database behavior
- Catches constraint violations, index issues, and performance problems
- Verifies migrations work correctly
- Gives true confidence in data access layer

## Required NuGet Packages

```xml
<ItemGroup>
  <PackageReference Include="Testcontainers" Version="*" />
  <PackageReference Include="xunit" Version="*" />
  <PackageReference Include="xunit.runner.visualstudio" Version="*" />

  <!-- Database-specific packages -->
  <PackageReference Include="Microsoft.Data.SqlClient" Version="*" />
  <PackageReference Include="Npgsql" Version="*" /> <!-- For PostgreSQL -->
  <PackageReference Include="MySqlConnector" Version="*" /> <!-- For MySQL -->

  <!-- Other infrastructure -->
  <PackageReference Include="StackExchange.Redis" Version="*" /> <!-- For Redis -->
  <PackageReference Include="RabbitMQ.Client" Version="*" /> <!-- For RabbitMQ -->
</ItemGroup>
```

## Getting Started

The Testcontainers library provides a simple API for managing Docker containers in your tests. Each test can spin up the infrastructure it needs, and Testcontainers handles the lifecycle automatically.

## Reference Documentation

For detailed patterns and examples, see the reference files:

- **[Database Containers](./reference/database-containers.md)** - SQL Server, PostgreSQL, MySQL, and migration patterns
- **[Message Broker Containers](./reference/message-broker-containers.md)** - RabbitMQ, Kafka, and Service Bus patterns
- **[Advanced Patterns](./reference/advanced-patterns.md)** - Networks, volumes, wait strategies, cleanup, and performance optimization

## Best Practices

1. **Always Use IAsyncLifetime** - Proper async setup and teardown
2. **Wait for Port Availability** - Use `WaitStrategy` to ensure containers are ready
3. **Use Random Ports** - Let TestContainers assign ports automatically
4. **Clean Data Between Tests** - Either use fresh containers or truncate tables
5. **Reuse Containers When Possible** - Faster than creating new ones for each test
6. **Test Real Queries** - Don't just test mocks; verify actual SQL behavior
7. **Verify Constraints** - Test foreign keys, unique constraints, indexes
8. **Test Transactions** - Verify rollback and commit behavior
9. **Use Realistic Data** - Test with production-like data volumes
10. **Handle Cleanup** - Always dispose containers in `DisposeAsync`
