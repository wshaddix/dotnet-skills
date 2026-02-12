# Message Broker Container Patterns

This reference covers patterns for using Testcontainers with message brokers in .NET integration tests.

## RabbitMQ Container

```csharp
public class RabbitMqTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _rabbitContainer;
    private IConnection _connection;

    public RabbitMqTests()
    {
        _rabbitContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("rabbitmq:management-alpine")
            .WithPortBinding(5672, true) // AMQP
            .WithPortBinding(15672, true) // Management UI
            .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(5672))
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _rabbitContainer.StartAsync();

        var port = _rabbitContainer.GetMappedPublicPort(5672);
        var factory = new ConnectionFactory
        {
            HostName = "localhost",
            Port = port,
            UserName = "guest",
            Password = "guest"
        };

        _connection = await factory.CreateConnectionAsync();
    }

    public async Task DisposeAsync()
    {
        await _connection.CloseAsync();
        await _rabbitContainer.DisposeAsync();
    }

    [Fact]
    public async Task RabbitMq_ShouldPublishAndConsumeMessage()
    {
        using var channel = await _connection.CreateChannelAsync();

        var queueName = "test-queue";
        await channel.QueueDeclareAsync(queueName, durable: false,
            exclusive: false, autoDelete: true);

        // Publish message
        var message = "Hello, RabbitMQ!";
        var body = Encoding.UTF8.GetBytes(message);
        await channel.BasicPublishAsync(exchange: "",
            routingKey: queueName,
            body: body);

        // Consume message
        var consumer = new EventingBasicConsumer(channel);
        var tcs = new TaskCompletionSource<string>();

        consumer.Received += (model, ea) =>
        {
            var receivedMessage = Encoding.UTF8.GetString(ea.Body.ToArray());
            tcs.SetResult(receivedMessage);
        };

        await channel.BasicConsumeAsync(queueName, autoAck: true,
            consumer: consumer);

        // Wait for message
        var received = await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(message, received);
    }
}
```

## Kafka Container

```csharp
public class KafkaTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _kafkaContainer;
    private readonly TestcontainersContainer _zookeeperContainer;
    private IProducer<string, string> _producer;
    private IConsumer<string, string> _consumer;

    public KafkaTests()
    {
        _zookeeperContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("confluentinc/cp-zookeeper:latest")
            .WithEnvironment("ZOOKEEPER_CLIENT_PORT", "2181")
            .WithPortBinding(2181, true)
            .Build();

        _kafkaContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("confluentinc/cp-kafka:latest")
            .WithEnvironment("KAFKA_BROKER_ID", "1")
            .WithEnvironment("KAFKA_ZOOKEEPER_CONNECT", "zookeeper:2181")
            .WithEnvironment("KAFKA_ADVERTISED_LISTENERS", "PLAINTEXT://localhost:9092")
            .WithEnvironment("KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR", "1")
            .WithPortBinding(9092, true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _zookeeperContainer.StartAsync();
        await _kafkaContainer.StartAsync();

        var bootstrapServers = $"localhost:{_kafkaContainer.GetMappedPublicPort(9092)}";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = bootstrapServers
        };
        _producer = new ProducerBuilder<string, string>(producerConfig).Build();

        var consumerConfig = new ConsumerConfig
        {
            BootstrapServers = bootstrapServers,
            GroupId = "test-group",
            AutoOffsetReset = AutoOffsetReset.Earliest
        };
        _consumer = new ConsumerBuilder<string, string>(consumerConfig).Build();
    }

    public async Task DisposeAsync()
    {
        _producer?.Dispose();
        _consumer?.Dispose();
        await _kafkaContainer.DisposeAsync();
        await _zookeeperContainer.DisposeAsync();
    }

    [Fact]
    public async Task Kafka_ShouldPublishAndConsumeMessage()
    {
        var topic = "test-topic";
        var message = "Hello, Kafka!";

        // Produce message
        await _producer.ProduceAsync(topic, new Message<string, string>
        {
            Key = "key1",
            Value = message
        });

        // Consume message
        _consumer.Subscribe(topic);
        var consumeResult = _consumer.Consume(TimeSpan.FromSeconds(10));

        Assert.NotNull(consumeResult);
        Assert.Equal(message, consumeResult.Message.Value);
    }
}
```

## Service Bus Container

Azure Service Bus doesn't have an official emulator container, but you can use the [Azure Service Bus Emulator](https://github.com/Azure/azure-service-bus-emulator) or test against the real service in isolated integration tests:

```csharp
public class ServiceBusTests : IAsyncLifetime
{
    private ServiceBusClient _client;
    private ServiceBusSender _sender;
    private ServiceBusReceiver _receiver;
    private readonly string _connectionString;

    public ServiceBusTests()
    {
        // Use Azure Service Bus emulator or test namespace connection string
        _connectionString = Environment.GetEnvironmentVariable("SERVICE_BUS_CONNECTION_STRING")
            ?? "Endpoint=sb://localhost:5672;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=test";
    }

    public async Task InitializeAsync()
    {
        _client = new ServiceBusClient(_connectionString);
        _sender = _client.CreateSender("test-queue");
        _receiver = _client.CreateReceiver("test-queue");
    }

    public async Task DisposeAsync()
    {
        await _sender.DisposeAsync();
        await _receiver.DisposeAsync();
        await _client.DisposeAsync();
    }

    [Fact]
    public async Task ServiceBus_ShouldSendAndReceiveMessage()
    {
        var message = new ServiceBusMessage("Hello, Service Bus!");

        // Send message
        await _sender.SendMessageAsync(message);

        // Receive message
        var receivedMessage = await _receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(10));

        Assert.NotNull(receivedMessage);
        Assert.Equal("Hello, Service Bus!", receivedMessage.Body.ToString());

        // Complete the message
        await _receiver.CompleteMessageAsync(receivedMessage);
    }
}
```

### Alternative: Using Azurite for Service Bus Testing

For local testing without Azure resources:

```csharp
public class ServiceBusEmulatorTests : IAsyncLifetime
{
    private readonly TestcontainersContainer _sqlEdgeContainer;
    private readonly TestcontainersContainer _emulatorContainer;

    public ServiceBusEmulatorTests()
    {
        // Service Bus emulator requires SQL Edge for persistence
        _sqlEdgeContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/azure-sql-edge:latest")
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("MSSQL_SA_PASSWORD", "YourStrong@Passw0rd")
            .WithPortBinding(1433, true)
            .Build();

        _emulatorContainer = new TestcontainersBuilder<TestcontainersContainer>()
            .WithImage("mcr.microsoft.com/azure-messaging/servicebus-emulator:latest")
            .WithEnvironment("SQL_SERVER", "sql-edge")
            .WithEnvironment("MSSQL_SA_PASSWORD", "YourStrong@Passw0rd")
            .WithPortBinding(5672, true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _sqlEdgeContainer.StartAsync();
        await _emulatorContainer.StartAsync();
    }

    public async Task DisposeAsync()
    {
        await _emulatorContainer.DisposeAsync();
        await _sqlEdgeContainer.DisposeAsync();
    }
}
```

## Required NuGet Packages

```xml
<ItemGroup>
  <!-- RabbitMQ -->
  <PackageReference Include="RabbitMQ.Client" Version="*" />

  <!-- Kafka -->
  <PackageReference Include="Confluent.Kafka" Version="*" />

  <!-- Azure Service Bus -->
  <PackageReference Include="Azure.Messaging.ServiceBus" Version="*" />
</ItemGroup>
```
