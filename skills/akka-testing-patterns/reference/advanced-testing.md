---
name: akka-net-testing-advanced-patterns
description: Advanced testing patterns for Akka.NET including cluster sharding testing, async actor behavior testing with AwaitAssertAsync, scenario-based integration tests, and Akka.Reminders testing.
---

# Advanced Testing Patterns Reference

This reference document contains advanced testing patterns for complex Akka.NET scenarios.

---

## Pattern 6: Testing Cluster Sharding Locally

Use `AkkaExecutionMode.LocalTest` to test cluster sharding behavior without an actual cluster.

```csharp
// In your production code (AkkaHostingExtensions.cs):
public static AkkaConfigurationBuilder WithOrderActor(
    this AkkaConfigurationBuilder builder,
    AkkaExecutionMode executionMode = AkkaExecutionMode.Clustered)
{
    if (executionMode == AkkaExecutionMode.LocalTest)
    {
        // Non-clustered mode: Use GenericChildPerEntityParent
        builder.WithActors((system, registry, resolver) =>
        {
            var parent = system.ActorOf(
                GenericChildPerEntityParent.CreateProps(
                    new OrderMessageExtractor(),
                    entityId => resolver.Props<OrderActor>(entityId)),
                "orders");

            registry.Register<OrderActor>(parent);
        });
    }
    else
    {
        // Clustered mode: Use ShardRegion
        builder.WithShardRegion<OrderActor>(
            "orders",
            (system, registry, resolver) => entityId => resolver.Props<OrderActor>(entityId),
            new OrderMessageExtractor(),
            new ShardOptions
            {
                StateStoreMode = StateStoreMode.DData,
                Role = "order-service"
            });
    }

    return builder;
}

// In your tests:
public class OrderShardingTests : TestKit
{
    protected override void ConfigureAkka(AkkaConfigurationBuilder builder, IServiceProvider provider)
    {
        builder.WithInMemoryJournal().WithInMemorySnapshotStore();

        // Use the same extension method as production, but with LocalTest mode
        builder.WithOrderActor(AkkaExecutionMode.LocalTest);
    }

    [Fact]
    public async Task ShardedActor_RoutesMessagesByEntityId()
    {
        // Arrange
        var orderRegion = ActorRegistry.Get<OrderActor>();

        // Act - Send commands for two different entity IDs
        var response1 = await orderRegion.Ask<OrderCommandResult>(
            new CreateOrder(OrderId: "ORDER-001", Amount: 100m),
            RemainingOrDefault);

        var response2 = await orderRegion.Ask<OrderCommandResult>(
            new CreateOrder(OrderId: "ORDER-002", Amount: 200m),
            RemainingOrDefault);

        // Assert
        response1.Status.Should().Be(CommandStatus.Success);
        response2.Status.Should().Be(CommandStatus.Success);

        // Query state to verify routing worked correctly
        var state1 = await orderRegion.Ask<OrderState>(
            new GetOrderState("ORDER-001"),
            RemainingOrDefault);
        var state2 = await orderRegion.Ask<OrderState>(
            new GetOrderState("ORDER-002"),
            RemainingOrDefault);

        state1.Amount.Should().Be(100m);
        state2.Amount.Should().Be(200m);
    }
}
```

**Key Patterns:**
- **Same extension methods** for production and tests
- **`AkkaExecutionMode` parameter** switches between clustered and local
- **`GenericChildPerEntityParent`** simulates sharding behavior locally
- **No actual cluster** needed for tests

---

## Pattern 6: Testing Asynchronous Actor Behavior with AwaitAssertAsync

Use `AwaitAssertAsync` when actors perform async operations (like calling external services).

```csharp
[Fact]
public async Task CreateInvoice_CallsReadModelSync()
{
    // Arrange
    var invoiceActor = ActorRegistry.Get<InvoiceActor>();
    var command = new CreateInvoice(InvoiceId: "INV-003", Amount: 75.00m);

    // Act
    var response = await invoiceActor.Ask<InvoiceCommandResult>(command, RemainingOrDefault);

    // Assert - Command succeeded
    response.Status.Should().Be(CommandStatus.Success);

    // Assert - Read model sync was called (async operation, need to wait)
    await AwaitAssertAsync(() =>
    {
        _fakeReadModelService.SyncCallCount.Should().BeGreaterOrEqualTo(1);
        _fakeReadModelService.LastSyncedInvoiceId.Should().Be("INV-003");
    }, TimeSpan.FromSeconds(3));
}

[Fact]
public async Task PaymentRetry_SchedulesReminder()
{
    // Arrange
    var invoiceActor = ActorRegistry.Get<InvoiceActor>();
    await CreateAndFailPayment(invoiceActor, "INV-004");

    // Act - Trigger payment failure (which schedules retry reminder)
    var failure = new PaymentFailed(InvoiceId: "INV-004", Reason: "Card declined");
    invoiceActor.Tell(failure);

    // Assert - Verify reminder was scheduled (async operation)
    var reminderClient = Sys.ReminderClient().CreateClient(
        new ReminderEntity("invoicing", "INV-004"));

    await AwaitAssertAsync(async () =>
    {
        var reminders = await reminderClient.ListRemindersAsync();
        reminders.Reminders.Should().HaveCount(1);
        reminders.Reminders.First().Key.Name.Should().Be("payment-retry");
    }, TimeSpan.FromSeconds(3));
}
```

**Key Patterns:**
- **AwaitAssertAsync** - Retries assertion until it passes or times out
- **Useful for async operations** - Read model syncs, reminder scheduling, external API calls
- **Prevents flaky tests** - Gives async operations time to complete

---

## Pattern 7: Scenario-Based Integration Tests

Test complete business workflows end-to-end with multiple actors and state transitions.

```csharp
public class SubscriptionScenarioTests : TestKit
{
    private readonly FakeSubscriptionService _fakeService;

    public SubscriptionScenarioTests(ITestOutputHelper output)
        : base(output: output, logLevel: LogLevel.Debug)
    {
        _fakeService = new FakeSubscriptionService();
    }

    protected override void ConfigureServices(HostBuilderContext context, IServiceCollection services)
    {
        services.AddSingleton<ISubscriptionService>(_fakeService);
        services.AddSingleton<IInvoiceService, FakeInvoiceService>();
        services.AddSingleton<IPaymentService, FakePaymentService>();
    }

    protected override void ConfigureAkka(AkkaConfigurationBuilder builder, IServiceProvider provider)
    {
        builder.AddHocon("akka.scheduler.implementation = \"Akka.TestKit.TestScheduler, Akka.TestKit\"",
            HoconAddMode.Prepend);

        builder.WithInMemoryJournal().WithInMemorySnapshotStore();

        // Register all domain actors (subscription, invoice, payment)
        builder.WithSubscriptionDomainActors(AkkaExecutionMode.LocalTest);
    }

    [Fact]
    public async Task Scenario_FirstTimePurchase_SuccessfulPayment()
    {
        // Arrange
        var subscriptionId = "SUB-001";
        var subscriptionActor = ActorRegistry.Get<SubscriptionActor>();

        // Step 1: Create subscription
        var createResult = await subscriptionActor.Ask<SubscriptionCommandResult>(
            new CreateSubscription(subscriptionId, "CUST-123", 99.99m),
            RemainingOrDefault);
        createResult.Status.Should().Be(CommandStatus.Success);

        // Step 2: Verify invoice was generated
        await AwaitAssertAsync(async () =>
        {
            var state = await subscriptionActor.Ask<SubscriptionState>(
                new GetSubscriptionState(subscriptionId),
                RemainingOrDefault);
            state.CurrentInvoiceId.Should().NotBeNullOrEmpty();
        });

        // Step 3: Simulate payment success
        var state = await subscriptionActor.Ask<SubscriptionState>(
            new GetSubscriptionState(subscriptionId),
            RemainingOrDefault);

        var paymentNotification = new PaymentCompleted(
            InvoiceId: state.CurrentInvoiceId!,
            Amount: 99.99m);
        subscriptionActor.Tell(paymentNotification);

        // Step 4: Verify subscription is now active
        await AwaitAssertAsync(async () =>
        {
            var finalState = await subscriptionActor.Ask<SubscriptionState>(
                new GetSubscriptionState(subscriptionId),
                RemainingOrDefault);
            finalState.Status.Should().Be(SubscriptionStatus.Active);
            finalState.BenefitsProvisioned.Should().BeTrue();
        });

        // Step 5: Verify service was provisioned
        _fakeService.ProvisionCallCount.Should().BeGreaterOrEqualTo(1);
        _fakeService.LastProvisionedSubscriptionId.Should().Be(subscriptionId);
    }

    [Fact]
    public async Task Scenario_PaymentFailure_RetryAndGracePeriod()
    {
        // Arrange
        var subscriptionId = "SUB-002";
        var subscriptionActor = ActorRegistry.Get<SubscriptionActor>();

        // Step 1: Create subscription and generate invoice
        await subscriptionActor.Ask<SubscriptionCommandResult>(
            new CreateSubscription(subscriptionId, "CUST-456", 199.99m),
            RemainingOrDefault);

        var state = await subscriptionActor.Ask<SubscriptionState>(
            new GetSubscriptionState(subscriptionId),
            RemainingOrDefault);
        var invoiceId = state.CurrentInvoiceId!;

        // Step 2: Simulate 3 payment failures
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            var failure = new PaymentFailed(
                InvoiceId: invoiceId,
                Reason: "Insufficient funds",
                CanRetry: true,
                AttemptNumber: attempt);

            subscriptionActor.Tell(failure);

            if (attempt < 3)
            {
                // Verify soft dunning notification for attempts 1-2
                await AwaitAssertAsync(async () =>
                {
                    var currentState = await subscriptionActor.Ask<SubscriptionState>(
                        new GetSubscriptionState(subscriptionId),
                        RemainingOrDefault);
                    currentState.PaymentRetryCount.Should().Be(attempt);
                });
            }
        }

        // Step 3: Verify hard dunning after 3 failures
        await AwaitAssertAsync(async () =>
        {
            var finalState = await subscriptionActor.Ask<SubscriptionState>(
                new GetSubscriptionState(subscriptionId),
                RemainingOrDefault);
            finalState.Status.Should().Be(SubscriptionStatus.PaymentFailed);
            finalState.GracePeriodExpiresAt.Should().NotBeNull();
        });

        // Step 4: Verify grace period reminder scheduled
        var reminderClient = Sys.ReminderClient().CreateClient(
            new ReminderEntity("subscription", subscriptionId));

        await AwaitAssertAsync(async () =>
        {
            var reminders = await reminderClient.ListRemindersAsync();
            reminders.Reminders.Should().ContainSingle(r =>
                r.Key.Name == "grace-period-expiration");
        });
    }
}
```

**Key Patterns:**
- **Multi-step workflows** - Test complete business scenarios, not just single operations
- **State verification at each step** - Use `AwaitAssertAsync` to verify state transitions
- **Multiple actors** - Register all domain actors, test their interactions
- **Business-focused naming** - `Scenario_FirstTimePurchase_SuccessfulPayment`

---

## Testing with Akka.Reminders

If your actors use Akka.Reminders for scheduling, configure local reminders in tests:

```csharp
protected override void ConfigureAkka(AkkaConfigurationBuilder builder, IServiceProvider provider)
{
    builder.AddHocon("akka.scheduler.implementation = \"Akka.TestKit.TestScheduler, Akka.TestKit\"",
        HoconAddMode.Prepend);

    builder.WithInMemoryJournal().WithInMemorySnapshotStore();

    // Configure local reminders for testing
    var shardResolver = new TestShardRegionResolver();

    builder.WithLocalReminders(reminders => reminders
        .WithInMemoryStorage()
        .WithResolver(shardResolver)
        .WithSettings(new ReminderSettings
        {
            MaxDeliveryAttempts = 5,
            RetryBackoffBase = TimeSpan.FromSeconds(1),
            MaxSlippage = TimeSpan.FromSeconds(60)
        }));

    builder.WithInvoicingActor(AkkaExecutionMode.LocalTest);

    // Register shard region with reminder resolver after startup
    builder.AddStartup(async (system, registry) =>
    {
        var invoicingRegion = await registry.GetAsync<InvoicingActor>();
        shardResolver.RegisterShardRegion("invoicing", invoicingRegion);
    });
}

[Fact]
public async Task PaymentFailure_SchedulesRetryReminder()
{
    // Arrange
    var invoiceId = "INV-001";
    var actor = ActorRegistry.Get<InvoicingActor>();

    // Act - Trigger payment failure
    var failure = new PaymentFailed(invoiceId, "Card declined");
    actor.Tell(failure);

    // Assert - Verify reminder was scheduled
    var reminderClient = Sys.ReminderClient().CreateClient(
        new ReminderEntity("invoicing", invoiceId));

    await AwaitAssertAsync(async () =>
    {
        var reminders = await reminderClient.ListRemindersAsync();
        reminders.Reminders.Should().HaveCount(1);
        reminders.Reminders.First().Key.Name.Should().Be("payment-retry");
    }, TimeSpan.FromSeconds(3));
}
```
