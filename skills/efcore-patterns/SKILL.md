---
name: efcore-patterns
description: Entity Framework Core best practices including NoTracking by default, query splitting for navigation collections, migration management, dedicated migration services, interceptors, compiled queries, and connection resiliency. Use when setting up EF Core in a new project, optimizing query performance, managing database migrations, integrating EF Core with .NET Aspire, or debugging change tracking issues.
---

# Entity Framework Core Patterns

## When to Use This Skill

Use this skill when:
- Setting up EF Core in a new project
- Optimizing query performance
- Managing database migrations
- Integrating EF Core with .NET Aspire
- Debugging change tracking issues
- Loading multiple navigation collections efficiently (query splitting)

## Core Principles

1. **NoTracking by Default** - Most queries are read-only; opt-in to tracking
2. **Never Edit Migrations Manually** - Always use CLI commands
3. **Dedicated Migration Service** - Separate migration execution from application startup
4. **ExecutionStrategy for Retries** - Handle transient database failures
5. **Explicit Updates** - When NoTracking, explicitly mark entities for update

---

## DbContext Lifecycle

`DbContext` is a unit of work and should be short-lived. In ASP.NET Core, register it as scoped (one per request):

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));
```

### Lifetime Rules

| Scenario | Lifetime | Registration |
|----------|----------|-------------|
| Web API / MVC request | Scoped (default) | `AddDbContext<T>()` |
| Background service | Scoped via factory | `AddDbContextFactory<T>()` |
| Blazor Server | Scoped via factory | `AddDbContextFactory<T>()` |
| Console app | Transient or manual | `new AppDbContext(options)` |

### DbContextFactory for Long-Lived Services

Background services and Blazor Server circuits outlive a single scope. Use `IDbContextFactory<T>`:

```csharp
public sealed class OrderProcessor(IDbContextFactory<AppDbContext> contextFactory)
{
    public async Task ProcessBatchAsync(CancellationToken ct)
    {
        await using var db = await contextFactory.CreateDbContextAsync(ct);

        var pending = await db.Orders
            .Where(o => o.Status == OrderStatus.Pending)
            .ToListAsync(ct);

        foreach (var order in pending)
        {
            order.Status = OrderStatus.Processing;
        }

        await db.SaveChangesAsync(ct);
    }
}

builder.Services.AddDbContextFactory<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));
```

### Pooling

`AddDbContextPool<T>()` reuses `DbContext` instances to reduce allocation overhead:

```csharp
builder.Services.AddDbContextPool<AppDbContext>(options =>
    options.UseNpgsql(connectionString), poolSize: 128);
```

**Pooling constraints:** Do not store per-request state on the `DbContext` subclass. Do not inject scoped services into the constructor.

---

## Pattern 1: NoTracking by Default

Configure your DbContext to disable change tracking by default:

```csharp
public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
        ChangeTracker.QueryTrackingBehavior = QueryTrackingBehavior.NoTracking;
    }

    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Customer> Customers => Set<Customer>();
}
```

### When NoTracking is Active

**Read-only queries work normally:**
```csharp
var orders = await dbContext.Orders
    .Where(o => o.Status == OrderStatus.Pending)
    .ToListAsync();
```

**Writes require explicit handling:**
```csharp
// WRONG - Entity not tracked, SaveChanges does nothing
var order = await dbContext.Orders.FirstOrDefaultAsync(o => o.Id == orderId);
order.Status = OrderStatus.Shipped;
await dbContext.SaveChangesAsync(); // Nothing happens!

// CORRECT - Explicitly mark entity for update
var order = await dbContext.Orders.FirstOrDefaultAsync(o => o.Id == orderId);
order.Status = OrderStatus.Shipped;
dbContext.Orders.Update(order);
await dbContext.SaveChangesAsync();

// ALSO CORRECT - Use AsTracking() for the query
var order = await dbContext.Orders
    .AsTracking()
    .FirstOrDefaultAsync(o => o.Id == orderId);
order.Status = OrderStatus.Shipped;
await dbContext.SaveChangesAsync();
```

### When to Use Tracking

| Scenario | Use Tracking? | Why |
|----------|---------------|-----|
| Display data in UI | No | Read-only, no updates |
| API GET endpoints | No | Returning data, no mutations |
| Update single entity | Yes or explicit Update() | Need to save changes |
| Complex update with navigation | Yes | Tracking handles relationships |
| Batch operations | No + ExecuteUpdate | More efficient |

### Per-Query NoTracking

```csharp
var orders = await db.Orders
    .AsNoTracking()
    .Where(o => o.CustomerId == customerId)
    .ToListAsync(ct);

var ordersWithItems = await db.Orders
    .AsNoTrackingWithIdentityResolution()
    .Include(o => o.Items)
    .Where(o => o.Status == OrderStatus.Active)
    .ToListAsync(ct);
```

---

## Pattern 2: Query Splitting to Prevent Cartesian Explosion

When loading multiple navigation collections via `Include()`, EF Core generates a single query that can cause cartesian explosion.

### The Problem

```csharp
// Single query: produces Cartesian product of OrderItems x Payments
var orders = await db.Orders
    .Include(o => o.Items)      // N items
    .Include(o => o.Payments)   // M payments
    .ToListAsync(ct);
// Result set: N x M rows per order
```

### The Solution

```csharp
var orders = await db.Orders
    .Include(o => o.Items)
    .Include(o => o.Payments)
    .AsSplitQuery()
    .ToListAsync(ct);
// Executes 3 separate queries: Orders, Items, Payments
```

### Global Default

```csharp
options.UseNpgsql(connectionString, npgsql =>
    npgsql.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery));
```

### Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| Single query (default) | Atomic snapshot, one round-trip | Cartesian explosion with multiple Includes |
| Split query | No Cartesian explosion, less data transfer | Multiple round-trips, no atomicity guarantee |

**Rule of thumb:** Use `AsSplitQuery()` when including two or more collection navigations.

---

## Pattern 3: Migration Management

**CRITICAL:** Always use EF Core CLI commands to manage migrations. Never manually edit migration files (except for custom SQL in `Up()`/`Down()`).

### Creating Migrations

```bash
dotnet ef migrations add AddCustomerTable \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api

dotnet ef migrations add AddCustomerTable \
    --context ApplicationDbContext \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api
```

### Removing Migrations

```bash
dotnet ef migrations remove \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api
```

### Applying Migrations

```bash
dotnet ef database update \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api

dotnet ef database update AddCustomerTable \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api

dotnet ef database update PreviousMigrationName \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api
```

### Generating SQL Scripts

```bash
dotnet ef migrations script \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --output migrations.sql

dotnet ef migrations script \
    --idempotent \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api
```

### Migration Bundles for Production

```bash
dotnet ef migrations bundle \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --output efbundle \
    --self-contained

./efbundle --connection "Host=prod-db;Database=myapp;Username=deploy;Password=..."
```

### Migration Best Practices

1. **Always generate idempotent scripts** for production (`--idempotent` flag)
2. **Never call `Database.Migrate()` at startup in production** -- use migration bundles or scripts
3. **Keep migrations additive** -- add columns with defaults, add tables, add indexes
4. **Review generated code** -- EF Core scaffolding can produce unexpected SQL
5. **Use separate migration projects** -- keep migrations in infrastructure project

### Data Seeding

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<OrderStatus>().HasData(
        new OrderStatus { Id = 1, Name = "Pending" },
        new OrderStatus { Id = 2, Name = "Processing" },
        new OrderStatus { Id = 3, Name = "Completed" },
        new OrderStatus { Id = 4, Name = "Cancelled" });
}
```

---

## Pattern 4: Dedicated Migration Service with Aspire

Separate migration execution from your main application.

### Project Structure

```
src/
├── MyApp.AppHost/           # Aspire orchestration
├── MyApp.Api/               # Main application
├── MyApp.Infrastructure/    # DbContext and migrations
└── MyApp.MigrationService/  # Dedicated migration runner
```

### MigrationWorker.cs

```csharp
public class MigrationWorker : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly IHostApplicationLifetime _hostApplicationLifetime;
    private readonly ILogger<MigrationWorker> _logger;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Migration service starting...");

        try
        {
            using var scope = _serviceProvider.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

            await RunMigrationsAsync(dbContext, stoppingToken);

            _logger.LogInformation("Migration service completed successfully.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Migration service failed: {Error}", ex.Message);
            throw;
        }
        finally
        {
            _hostApplicationLifetime.StopApplication();
        }
    }

    private async Task RunMigrationsAsync(ApplicationDbContext dbContext, CancellationToken ct)
    {
        var strategy = dbContext.Database.CreateExecutionStrategy();

        await strategy.ExecuteAsync(async () =>
        {
            var pendingMigrations = await dbContext.Database.GetPendingMigrationsAsync(ct);

            if (pendingMigrations.Any())
            {
                _logger.LogInformation("Applying {Count} pending migrations...",
                    pendingMigrations.Count());

                await dbContext.Database.MigrateAsync(ct);

                _logger.LogInformation("Migrations applied successfully.");
            }
            else
            {
                _logger.LogInformation("No pending migrations. Database is up to date.");
            }
        });
    }
}
```

### AppHost Configuration

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var postgres = builder.AddPostgres("postgres");
var db = postgres.AddDatabase("appdb");

var migrations = builder.AddProject<Projects.MyApp_MigrationService>("migrations")
    .WaitFor(db)
    .WithReference(db);

var api = builder.AddProject<Projects.MyApp_Api>("api")
    .WaitForCompletion(migrations)
    .WithReference(db);
```

---

## Pattern 5: ExecutionStrategy for Transient Failures

Always use `CreateExecutionStrategy()` for operations that might fail transiently:

```csharp
public async Task UpdateWithRetryAsync(Guid id, Action<Order> update)
{
    var strategy = _dbContext.Database.CreateExecutionStrategy();

    await strategy.ExecuteAsync(async () =>
    {
        var order = await _dbContext.Orders
            .AsTracking()
            .FirstOrDefaultAsync(o => o.Id == id);

        if (order is null) return;

        update(order);
        await _dbContext.SaveChangesAsync();
    });
}
```

### With Transactions

```csharp
var strategy = _dbContext.Database.CreateExecutionStrategy();

await strategy.ExecuteAsync(async () =>
{
    await using var transaction = await _dbContext.Database.BeginTransactionAsync();

    try
    {
        await _dbContext.SaveChangesAsync();
        await transaction.CommitAsync();
    }
    catch
    {
        await transaction.RollbackAsync();
        throw;
    }
});
```

### Provider-Specific Configuration

```csharp
// PostgreSQL
options.UseNpgsql(connectionString, npgsql =>
    npgsql.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(30),
        errorCodesToAdd: null));

// SQL Server
options.UseSqlServer(connectionString, sqlServer =>
    sqlServer.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(30),
        errorNumbersToAdd: null));
```

---

## Pattern 6: Interceptors

EF Core interceptors allow cross-cutting concerns without modifying entity logic.

### Audit Timestamp Interceptor

```csharp
public sealed class AuditTimestampInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken ct = default)
    {
        if (eventData.Context is null)
            return ValueTask.FromResult(result);

        var now = DateTimeOffset.UtcNow;

        foreach (var entry in eventData.Context.ChangeTracker.Entries<IAuditable>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    entry.Entity.CreatedAt = now;
                    entry.Entity.UpdatedAt = now;
                    break;
                case EntityState.Modified:
                    entry.Entity.UpdatedAt = now;
                    break;
            }
        }

        return ValueTask.FromResult(result);
    }
}

public interface IAuditable
{
    DateTimeOffset CreatedAt { get; set; }
    DateTimeOffset UpdatedAt { get; set; }
}
```

### Soft Delete Interceptor

```csharp
public sealed class SoftDeleteInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken ct = default)
    {
        if (eventData.Context is null)
            return ValueTask.FromResult(result);

        foreach (var entry in eventData.Context.ChangeTracker.Entries<ISoftDeletable>())
        {
            if (entry.State == EntityState.Deleted)
            {
                entry.State = EntityState.Modified;
                entry.Entity.IsDeleted = true;
                entry.Entity.DeletedAt = DateTimeOffset.UtcNow;
            }
        }

        return ValueTask.FromResult(result);
    }
}

protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<Product>()
        .HasQueryFilter(p => !p.IsDeleted);
}
```

### Registration

```csharp
builder.Services.AddDbContext<AppDbContext>((sp, options) =>
    options.UseNpgsql(connectionString)
           .AddInterceptors(
               sp.GetRequiredService<AuditTimestampInterceptor>(),
               sp.GetRequiredService<SoftDeleteInterceptor>()));

builder.Services.AddSingleton<AuditTimestampInterceptor>();
builder.Services.AddSingleton<SoftDeleteInterceptor>();
```

---

## Pattern 7: Compiled Queries

For queries executed very frequently:

```csharp
public static class CompiledQueries
{
    public static readonly Func<AppDbContext, int, Task<Order?>>
        GetOrderById = EF.CompileAsyncQuery(
            (AppDbContext db, int orderId) =>
                db.Orders
                    .AsNoTracking()
                    .Include(o => o.Items)
                    .FirstOrDefault(o => o.Id == orderId));

    public static readonly Func<AppDbContext, string, IAsyncEnumerable<Order>>
        GetOrdersByCustomer = EF.CompileAsyncQuery(
            (AppDbContext db, string customerId) =>
                db.Orders
                    .AsNoTracking()
                    .Where(o => o.CustomerId == customerId)
                    .OrderByDescending(o => o.CreatedAt));
}

var order = await CompiledQueries.GetOrderById(db, orderId);

await foreach (var o in CompiledQueries.GetOrdersByCustomer(db, customerId)
    .WithCancellation(ct))
{
}
```

**When to use:** Queries that execute thousands of times per second. For typical CRUD, standard LINQ is sufficient.

---

## Pattern 8: Bulk Operations

Use EF Core 7+ `ExecuteUpdateAsync` and `ExecuteDeleteAsync`:

```csharp
// WRONG - Loads all entities into memory
var expiredOrders = await _db.Orders
    .Where(o => o.ExpiresAt < DateTimeOffset.UtcNow)
    .ToListAsync();

foreach (var order in expiredOrders)
{
    order.Status = OrderStatus.Expired;
}
await _db.SaveChangesAsync();

// CORRECT - Single SQL UPDATE statement
await _db.Orders
    .Where(o => o.ExpiresAt < DateTimeOffset.UtcNow)
    .ExecuteUpdateAsync(setters => setters
        .SetProperty(o => o.Status, OrderStatus.Expired)
        .SetProperty(o => o.UpdatedAt, DateTimeOffset.UtcNow));

await _db.Orders
    .Where(o => o.Status == OrderStatus.Cancelled && o.CreatedAt < cutoffDate)
    .ExecuteDeleteAsync();
```

---

## Common Pitfalls

### 1. Forgetting to Update When NoTracking

```csharp
// Silent failure - entity not tracked
var customer = await _db.Customers.FindAsync(id);
customer.Name = "New Name";
await _db.SaveChangesAsync(); // Does nothing!

// Explicit update
var customer = await _db.Customers.FindAsync(id);
customer.Name = "New Name";
_db.Customers.Update(customer);
await _db.SaveChangesAsync();
```

### 2. N+1 Query Problem

```csharp
// N+1 queries - one query per order
var customers = await _db.Customers.ToListAsync();
foreach (var customer in customers)
{
    var orders = customer.Orders; // Lazy load triggers query
}

// Eager loading - single query
var customers = await _db.Customers
    .Include(c => c.Orders)
    .ToListAsync();
```

### 3. Tracking Conflicts

```csharp
// Tracking conflict
var order1 = await _db1.Orders.AsTracking().FindAsync(id);
var order2 = await _db2.Orders.AsTracking().FindAsync(id);
order2.Status = OrderStatus.Shipped;
await _db2.SaveChangesAsync();

// Use single context or detach
_db1.Entry(order1).State = EntityState.Detached;
```

### 4. Querying Inside Loops

```csharp
// Query per iteration
foreach (var orderId in orderIds)
{
    var order = await _db.Orders.FindAsync(orderId);
}

// Single query
var orders = await _db.Orders
    .Where(o => orderIds.Contains(o.Id))
    .ToListAsync();
```

---

## Testing with EF Core

### In-Memory Provider (Unit Tests Only)

```csharp
var options = new DbContextOptionsBuilder<ApplicationDbContext>()
    .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
    .Options;

using var context = new ApplicationDbContext(options);
```

### Real Database with TestContainers

```csharp
var container = new PostgreSqlBuilder()
    .WithImage("postgres:16-alpine")
    .Build();

await container.StartAsync();

var options = new DbContextOptionsBuilder<ApplicationDbContext>()
    .UseNpgsql(container.GetConnectionString())
    .Options;
```

---

## Agent Gotchas

1. **Do not inject `DbContext` into singleton services** -- use `IDbContextFactory<T>` instead.
2. **Do not forget `CancellationToken` propagation** -- pass `ct` to all async EF Core methods.
3. **Do not use `Database.EnsureCreated()` alongside migrations** -- use only in test scenarios.
4. **Do not assume `SaveChangesAsync` is transactional across multiple calls** -- wrap in explicit transaction.
5. **Do not hardcode connection strings** -- read from configuration.
6. **Always pass `validateAllProperties: true`** to `Validator.TryValidateObject`.

---

## References

- [EF Core performance best practices](https://learn.microsoft.com/en-us/ef/core/performance/)
- [DbContext lifetime, configuration, and initialization](https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/)
- [EF Core interceptors](https://learn.microsoft.com/en-us/ef/core/logging-events-diagnostics/interceptors)
- [EF Core migrations overview](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/)
- [EF Core compiled queries](https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics#compiled-queries)
- [EF Core connection resiliency](https://learn.microsoft.com/en-us/ef/core/miscellaneous/connection-resiliency)
