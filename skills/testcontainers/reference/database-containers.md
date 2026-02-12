# Database Container Patterns

This reference covers patterns for using Testcontainers with various databases in .NET integration tests.

## SQL Server Container

```csharp
using Testcontainers;
using Xunit;

public class SqlServerTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _dbContainer;
    private IDbConnection _db;

    public SqlServerTests()
    {
        _dbContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("SA_PASSWORD", "Your_password123")
            .WithPortBinding(1433, true)
            .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(1433))
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _dbContainer.StartAsync();

        var port = _dbContainer.GetMappedPublicPort(1433);
        var connectionString = $"Server=localhost,{port};Database=master;User Id=sa;Password=Your_password123;TrustServerCertificate=true";

        _db = new SqlConnection(connectionString);
        await _db.OpenAsync();

        // Create test database
        await _db.ExecuteAsync("CREATE DATABASE TestDb");
        await _db.ExecuteAsync("USE TestDb");

        // Run schema migrations
        await _db.ExecuteAsync(@"
            CREATE TABLE Orders (
                Id INT PRIMARY KEY,
                CustomerId NVARCHAR(50) NOT NULL,
                Total DECIMAL(18,2) NOT NULL,
                CreatedAt DATETIME2 DEFAULT GETUTCDATE()
            )");
    }

    public async Task DisposeAsync()
    {
        await _db.DisposeAsync();
        await _dbContainer.DisposeAsync();
    }

    [Fact]
    public async Task CanInsertAndRetrieveOrder()
    {
        // Arrange
        await _db.ExecuteAsync(@"
            INSERT INTO Orders (Id, CustomerId, Total)
            VALUES (1, 'CUST001', 99.99)");

        // Act
        var order = await _db.QuerySingleAsync<Order>(
            "SELECT * FROM Orders WHERE Id = @Id",
            new { Id = 1 });

        // Assert
        Assert.Equal(1, order.Id);
        Assert.Equal("CUST001", order.CustomerId);
        Assert.Equal(99.99m, order.Total);
    }
}
```

## PostgreSQL Container

```csharp
public class PostgreSqlTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _dbContainer;
    private NpgsqlConnection _connection;

    public PostgreSqlTests()
    {
        _dbContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("postgres:latest")
            .WithEnvironment("POSTGRES_PASSWORD", "postgres")
            .WithEnvironment("POSTGRES_DB", "testdb")
            .WithPortBinding(5432, true)
            .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(5432))
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _dbContainer.StartAsync();

        var port = _dbContainer.GetMappedPublicPort(5432);
        var connectionString = $"Host=localhost;Port={port};Database=testdb;Username=postgres;Password=postgres";

        _connection = new NpgsqlConnection(connectionString);
        await _connection.OpenAsync();

        // Create schema
        await _connection.ExecuteAsync(@"
            CREATE TABLE orders (
                id SERIAL PRIMARY KEY,
                customer_id VARCHAR(50) NOT NULL,
                total NUMERIC(10,2) NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )");
    }

    public async Task DisposeAsync()
    {
        await _connection.DisposeAsync();
        await _dbContainer.DisposeAsync();
    }

    [Fact]
    public async Task PostgreSql_ShouldHandleTransactions()
    {
        using var transaction = await _connection.BeginTransactionAsync();

        await _connection.ExecuteAsync(
            "INSERT INTO orders (customer_id, total) VALUES (@CustomerId, @Total)",
            new { CustomerId = "CUST1", Total = 100.00m },
            transaction);

        await transaction.RollbackAsync();

        var count = await _connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM orders");

        Assert.Equal(0, count); // Rollback should prevent insert
    }
}
```

## MySQL Container

```csharp
public class MySqlTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _dbContainer;
    private MySqlConnection _connection;

    public MySqlTests()
    {
        _dbContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mysql:latest")
            .WithEnvironment("MYSQL_ROOT_PASSWORD", "rootpassword")
            .WithEnvironment("MYSQL_DATABASE", "testdb")
            .WithPortBinding(3306, true)
            .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(3306))
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _dbContainer.StartAsync();

        var port = _dbContainer.GetMappedPublicPort(3306);
        var connectionString = $"Server=localhost;Port={port};Database=testdb;Uid=root;Pwd=rootpassword;";

        _connection = new MySqlConnection(connectionString);
        await _connection.OpenAsync();

        // Create schema
        await _connection.ExecuteAsync(@"
            CREATE TABLE orders (
                id INT AUTO_INCREMENT PRIMARY KEY,
                customer_id VARCHAR(50) NOT NULL,
                total DECIMAL(10,2) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )");
    }

    public async Task DisposeAsync()
    {
        await _connection.DisposeAsync();
        await _dbContainer.DisposeAsync();
    }

    [Fact]
    public async Task MySql_ShouldInsertAndRetrieve()
    {
        await _connection.ExecuteAsync(
            "INSERT INTO orders (customer_id, total) VALUES (@CustomerId, @Total)",
            new { CustomerId = "CUST1", Total = 100.00m });

        var order = await _connection.QuerySingleAsync<Order>(
            "SELECT * FROM orders WHERE customer_id = @CustomerId",
            new { CustomerId = "CUST1" });

        Assert.NotNull(order);
        Assert.Equal(100.00m, order.Total);
    }
}
```

## Database Migration Patterns

### Testing Migrations with Real Databases

```csharp
public class MigrationTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _container;
    private string _connectionString;

    public async Task InitializeAsync()
    {
        _container = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("SA_PASSWORD", "Your_password123")
            .WithPortBinding(1433, true)
            .Build();

        await _container.StartAsync();

        var port = _container.GetMappedPublicPort(1433);
        _connectionString = $"Server=localhost,{port};Database=TestDb;User Id=sa;Password=Your_password123;TrustServerCertificate=true";
    }

    [Fact]
    public async Task Migrations_ShouldRunSuccessfully()
    {
        // Run Entity Framework migrations
        var optionsBuilder = new DbContextOptionsBuilder<AppDbContext>();
        optionsBuilder.UseSqlServer(_connectionString);

        using var context = new AppDbContext(optionsBuilder.Options);

        // Apply migrations
        await context.Database.MigrateAsync();

        // Verify schema
        var canConnect = await context.Database.CanConnectAsync();
        Assert.True(canConnect);

        // Verify tables exist
        var tables = await context.Database.SqlQueryRaw<string>(
            "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES").ToListAsync();

        Assert.Contains("Orders", tables);
        Assert.Contains("Customers", tables);
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}
```

### Database Reset with Respawn

When reusing containers across tests, use [Respawn](https://github.com/jbogard/Respawn) to reset database state between tests instead of recreating containers:

```xml
<PackageReference Include="Respawn" Version="*" />
```

#### Basic Respawn Setup

```csharp
using Respawn;

public class DatabaseFixture : IAsyncLifetime
{
    private readonly TestcontainersContainer _container;
    private Respawner _respawner = null!;
    public NpgsqlConnection Connection { get; private set; } = null!;
    public string ConnectionString { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        await _container.StartAsync();

        var port = _container.GetMappedPublicPort(5432);
        ConnectionString = $"Host=localhost;Port={port};Database=testdb;Username=postgres;Password=postgres";

        Connection = new NpgsqlConnection(ConnectionString);
        await Connection.OpenAsync();

        // Run migrations first
        await RunMigrationsAsync();

        // Create respawner after schema exists
        _respawner = await Respawner.CreateAsync(ConnectionString, new RespawnerOptions
        {
            TablesToIgnore = new Table[]
            {
                "__EFMigrationsHistory",  // EF Core migrations table
                "AspNetRoles",            // Identity roles (seeded data)
                "schema_version"          // DbUp/Flyway version table
            },
            DbAdapter = DbAdapter.Postgres
        });
    }

    /// <summary>
    /// Reset database to clean state. Call this in test setup or between tests.
    /// </summary>
    public async Task ResetDatabaseAsync()
    {
        await _respawner.ResetAsync(ConnectionString);
    }

    public async Task DisposeAsync()
    {
        await Connection.DisposeAsync();
        await _container.DisposeAsync();
    }
}
```

#### Using Respawn in Tests

```csharp
[Collection("Database collection")]
public class OrderTests : IAsyncLifetime
{
    private readonly DatabaseFixture _fixture;

    public OrderTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    public async Task InitializeAsync()
    {
        // Reset database before each test
        await _fixture.ResetDatabaseAsync();
    }

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task CreateOrder_ShouldPersist()
    {
        // Database is clean - no leftover data from other tests
        await _fixture.Connection.ExecuteAsync(
            "INSERT INTO orders (customer_id, total) VALUES (@CustomerId, @Total)",
            new { CustomerId = "CUST1", Total = 100.00m });

        var count = await _fixture.Connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM orders");

        Assert.Equal(1, count);
    }

    [Fact]
    public async Task AnotherTest_StartsWithCleanDatabase()
    {
        // This test also starts with empty tables
        var count = await _fixture.Connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM orders");

        Assert.Equal(0, count); // Clean slate!
    }
}
```

#### Respawn Options

```csharp
var respawner = await Respawner.CreateAsync(connectionString, new RespawnerOptions
{
    // Tables to preserve (reference data, migrations history)
    TablesToIgnore = new Table[]
    {
        "__EFMigrationsHistory",
        new Table("public", "lookup_data"),  // Schema-qualified
    },

    // Schemas to clean (default: all schemas)
    SchemasToInclude = new[] { "public", "app" },

    // Or exclude specific schemas
    SchemasToExclude = new[] { "audit", "logging" },

    // Database adapter
    DbAdapter = DbAdapter.Postgres,  // or SqlServer, MySql

    // Handle circular foreign keys
    WithReseed = true  // Reset identity columns (SQL Server)
});
```

#### Why Respawn Over Container Recreation

| Approach | Pros | Cons |
|----------|------|------|
| **New container per test** | Complete isolation | Slow (10-30s per container) |
| **Respawn** | Fast (~50ms), preserves schema/migrations | Requires careful table exclusion |
| **Transaction rollback** | Fastest | Can't test commit behavior |

**Use Respawn when:**
- Tests share a container via xUnit collection fixture
- You need to test actual commits (not just rollbacks)
- Container startup time is a bottleneck
