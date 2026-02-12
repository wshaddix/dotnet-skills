---
name: signalr-integration
description: SignalR integration patterns for real-time communication in ASP.NET Core Razor Pages applications. Use when implementing real-time features in ASP.NET Core applications, setting up SignalR hubs and clients, or managing WebSocket connections and groups.
---

## Rationale

Real-time communication enhances user experience with instant updates, notifications, and collaborative features. SignalR provides a robust framework for bidirectional communication between server and clients. Without proper patterns, applications can suffer from connection leaks, scalability issues, and security vulnerabilities. These patterns provide production-ready approaches to SignalR in Razor Pages applications.

## Patterns

### Pattern 1: Hub Structure and Organization

Organize hubs by domain with proper authentication and group management.

```csharp
// Base hub with common functionality
public abstract class AuthenticatedHub : Hub
{
    protected string? UserId => Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    protected bool IsAuthenticated => !string.IsNullOrEmpty(UserId);

    public override async Task OnConnectedAsync()
    {
        if (!IsAuthenticated)
        {
            Context.Abort();
            return;
        }

        await base.OnConnectedAsync();
    }
}

// Notification hub for real-time updates
public interface INotificationClient
{
    Task ReceiveNotification(NotificationMessage message);
    Task NotificationRead(string notificationId);
    Task UnreadCountUpdated(int count);
}

public class NotificationHub : AuthenticatedHub<INotificationClient>
{
    private readonly INotificationService _notificationService;
    private readonly ILogger<NotificationHub> _logger;

    public NotificationHub(
        INotificationService notificationService,
        ILogger<NotificationHub> logger)
    {
        _notificationService = notificationService;
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        await base.OnConnectedAsync();

        if (UserId != null)
        {
            // Join user-specific group
            await Groups.AddToGroupAsync(Context.ConnectionId, $"user:{UserId}");
            
            // Send initial unread count
            var count = await _notificationService.GetUnreadCountAsync(UserId);
            await Clients.Caller.UnreadCountUpdated(count);
            
            _logger.LogDebug("User {UserId} connected to notification hub", UserId);
        }
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        if (UserId != null)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"user:{UserId}");
            _logger.LogDebug("User {UserId} disconnected from notification hub", UserId);
        }

        await base.OnDisconnectedAsync(exception);
    }

    public async Task MarkAsRead(string notificationId)
    {
        if (UserId == null) return;

        await _notificationService.MarkAsReadAsync(UserId, notificationId);
        
        var count = await _notificationService.GetUnreadCountAsync(UserId);
        await Clients.Caller.UnreadCountUpdated(count);
    }

    public async Task SubscribeToTopic(string topic)
    {
        // Validate topic access
        if (!await CanSubscribeToTopic(topic))
        {
            throw new HubException("Not authorized for this topic");
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, $"topic:{topic}");
    }

    private Task<bool> CanSubscribeToTopic(string topic)
    {
        // Implement topic authorization logic
        return Task.FromResult(true);
    }
}

// Order status hub for real-time order updates
public interface IOrderClient
{
    Task OrderStatusUpdated(string orderId, OrderStatus status, string? message);
    Task OrderProgressUpdated(string orderId, int progressPercent);
    Task OrderCompleted(string orderId);
}

public class OrderHub : AuthenticatedHub<IOrderClient>
{
    private readonly IOrderService _orderService;

    public OrderHub(IOrderService orderService)
    {
        _orderService = orderService;
    }

    public async Task SubscribeToOrder(string orderId)
    {
        if (UserId == null) return;

        // Verify user owns this order
        var order = await _orderService.GetOrderAsync(orderId);
        if (order?.UserId != UserId)
        {
            throw new HubException("Not authorized to view this order");
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, $"order:{orderId}");
    }

    public async Task UnsubscribeFromOrder(string orderId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"order:{orderId}");
    }
}
```

### Pattern 2: Razor Pages Integration

Integrate SignalR clients in Razor Pages with proper connection lifecycle management.

```csharp
// SignalR configuration in Program.cs
builder.Services.AddSignalR()
    .AddJsonProtocol(options =>
    {
        options.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    })
    .AddStackExchangeRedis("redis:6379"); // For scale-out

// Authentication for SignalR
builder.Services.AddAuthentication()
    .AddCookie(options =>
    {
        // Allow SignalR to use cookie auth
        options.Events.OnRedirectToLogin = context =>
        {
            context.Response.StatusCode = 401;
            return Task.CompletedTask;
        };
    });

// Hub endpoints
app.MapHub<NotificationHub>("/hubs/notifications")
    .RequireAuthorization();

app.MapHub<OrderHub>("/hubs/orders")
    .RequireAuthorization();
```

```javascript
// wwwroot/js/signalr-client.js
class SignalRClient {
    constructor() {
        this.connections = new Map();
        this.reconnectDelays = [0, 2000, 5000, 10000, 30000];
    }

    async connect(hubUrl, hubName) {
        if (this.connections.has(hubName)) {
            return this.connections.get(hubName);
        }

        const connection = new signalR.HubConnectionBuilder()
            .withUrl(hubUrl, {
                transport: signalR.HttpTransportType.WebSockets |
                          signalR.HttpTransportType.ServerSentEvents
            })
            .withAutomaticReconnect(this.reconnectDelays)
            .configureLogging(signalR.LogLevel.Information)
            .build();

        connection.onreconnecting(error => {
            console.log(`Reconnecting to ${hubName}...`, error);
            this.showReconnectingUI(hubName);
        });

        connection.onreconnected(connectionId => {
            console.log(`Reconnected to ${hubName}`, connectionId);
            this.hideReconnectingUI(hubName);
        });

        connection.onclose(error => {
            console.log(`Connection to ${hubName} closed`, error);
            this.connections.delete(hubName);
            this.showDisconnectedUI(hubName);
        });

        try {
            await connection.start();
            this.connections.set(hubName, connection);
            console.log(`Connected to ${hubName}`);
            return connection;
        } catch (err) {
            console.error(`Failed to connect to ${hubName}`, err);
            throw err;
        }
    }

    async disconnect(hubName) {
        const connection = this.connections.get(hubName);
        if (connection) {
            await connection.stop();
            this.connections.delete(hubName);
        }
    }

    getConnection(hubName) {
        return this.connections.get(hubName);
    }

    showReconnectingUI(hubName) {
        document.body.classList.add('signalr-reconnecting');
    }

    hideReconnectingUI(hubName) {
        document.body.classList.remove('signalr-reconnecting');
    }

    showDisconnectedUI(hubName) {
        document.body.classList.add('signalr-disconnected');
    }
}

// Global instance
window.signalRClient = new SignalRClient();
```

```csharp
// Razor Page with SignalR integration
public class OrderStatusModel : PageModel
{
    private readonly IOrderService _orderService;

    public OrderStatusModel(IOrderService orderService)
    {
        _orderService = orderService;
    }

    public Order Order { get; set; } = null!;

    public async Task<IActionResult> OnGetAsync(string orderId)
    {
        Order = await _orderService.GetOrderAsync(orderId);
        
        if (Order == null || Order.UserId != User.FindFirstValue(ClaimTypes.NameIdentifier))
        {
            return NotFound();
        }

        return Page();
    }
}
```

```html
<!-- OrderStatus.cshtml -->
@page "{orderId}"
@model OrderStatusModel
@inject IConfiguration Configuration

@section Scripts {
    <script src="~/lib/microsoft/signalr/dist/browser/signalr.min.js"></script>
    <script src="~/js/signalr-client.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', async function() {
            const orderId = '@Model.Order.Id';
            
            try {
                const connection = await window.signalRClient.connect(
                    '/hubs/orders',
                    'orders'
                );

                // Subscribe to order updates
                await connection.invoke('SubscribeToOrder', orderId);

                // Handle status updates
                connection.on('OrderStatusUpdated', (id, status, message) => {
                    if (id === orderId) {
                        updateStatusUI(status, message);
                    }
                });

                connection.on('OrderProgressUpdated', (id, progress) => {
                    if (id === orderId) {
                        updateProgressBar(progress);
                    }
                });

                connection.on('OrderCompleted', (id) => {
                    if (id === orderId) {
                        showCompletionUI();
                    }
                });

            } catch (err) {
                console.error('Failed to connect:', err);
                showFallbackUI();
            }
        });

        function updateStatusUI(status, message) {
            document.getElementById('status-badge').textContent = status;
            if (message) {
                document.getElementById('status-message').textContent = message;
            }
        }

        function updateProgressBar(progress) {
            const bar = document.getElementById('progress-bar');
            bar.style.width = progress + '%';
            bar.textContent = progress + '%';
        }

        function showCompletionUI() {
            document.getElementById('completion-modal').classList.remove('hidden');
        }

        function showFallbackUI() {
            // Fall back to polling
            setInterval(() => location.reload(), 30000);
        }
    </script>
}

<div class="order-status">
    <h1>Order #@Model.Order.Id</h1>
    <span id="status-badge" class="badge">@Model.Order.Status</span>
    <p id="status-message" class="text-muted"></p>
    
    <div class="progress">
        <div id="progress-bar" class="progress-bar" style="width: 0%">0%</div>
    </div>
</div>

<div id="completion-modal" class="modal hidden">
    <div class="modal-content">
        <h2>Order Complete!</h2>
        <p>Your order has been processed successfully.</p>
    </div>
</div>
```

### Pattern 3: Server-Side Broadcasting

Send notifications from services and background workers to connected clients.

```csharp
// Notification service that broadcasts to clients
public interface IRealTimeNotificationService
{
    Task SendToUserAsync(string userId, NotificationMessage message);
    Task SendToUsersAsync(IEnumerable<string> userIds, NotificationMessage message);
    Task BroadcastToTopicAsync(string topic, NotificationMessage message);
    Task SendToGroupAsync(string groupName, NotificationMessage message);
}

public class SignalRNotificationService : IRealTimeNotificationService
{
    private readonly IHubContext<NotificationHub, INotificationClient> _hubContext;
    private readonly ILogger<SignalRNotificationService> _logger;

    public SignalRNotificationService(
        IHubContext<NotificationHub, INotificationClient> hubContext,
        ILogger<SignalRNotificationService> logger)
    {
        _hubContext = hubContext;
        _logger = logger;
    }

    public async Task SendToUserAsync(string userId, NotificationMessage message)
    {
        try
        {
            await _hubContext.Clients.Group($"user:{userId}")
                .ReceiveNotification(message);
            
            _logger.LogDebug("Notification sent to user {UserId}", userId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send notification to user {UserId}", userId);
        }
    }

    public async Task SendToUsersAsync(IEnumerable<string> userIds, NotificationMessage message)
    {
        var tasks = userIds.Select(userId => SendToUserAsync(userId, message));
        await Task.WhenAll(tasks);
    }

    public async Task BroadcastToTopicAsync(string topic, NotificationMessage message)
    {
        await _hubContext.Clients.Group($"topic:{topic}")
            .ReceiveNotification(message);
    }

    public async Task SendToGroupAsync(string groupName, NotificationMessage message)
    {
        await _hubContext.Clients.Group(groupName)
            .ReceiveNotification(message);
    }

    public async Task UpdateUnreadCountAsync(string userId, int count)
    {
        await _hubContext.Clients.Group($"user:{userId}")
            .UnreadCountUpdated(count);
    }
}

// Background service that sends notifications
public class OrderProcessingNotifier : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<OrderProcessingNotifier> _logger;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = _serviceProvider.CreateAsyncScope();
                var orderService = scope.ServiceProvider.GetRequiredService<IOrderService>();
                var notificationService = scope.ServiceProvider.GetRequiredService<IRealTimeNotificationService>();

                // Get orders that need status updates
                var ordersToUpdate = await orderService.GetOrdersNeedingUpdatesAsync(stoppingToken);

                foreach (var order in ordersToUpdate)
                {
                    await notificationService.SendToUserAsync(
                        order.UserId,
                        new NotificationMessage
                        {
                            Id = Guid.NewGuid().ToString(),
                            Title = "Order Update",
                            Message = $"Your order #{order.Id} status changed to {order.Status}",
                            Type = NotificationType.OrderUpdate,
                            Data = new Dictionary<string, object>
                            {
                                ["orderId"] = order.Id,
                                ["status"] = order.Status
                            }
                        });

                    await notificationService.UpdateUnreadCountAsync(
                        order.UserId,
                        await orderService.GetUnreadNotificationCountAsync(order.UserId));
                }

                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in order processing notifier");
                await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
            }
        }
    }
}
```

### Pattern 4: Connection Management and Scale-Out

Handle connection scaling with Redis backplane and connection state management.

```csharp
// Connection tracking service
public interface IConnectionTracker
{
    Task AddConnectionAsync(string userId, string connectionId);
    Task RemoveConnectionAsync(string userId, string connectionId);
    Task<IReadOnlyList<string>> GetUserConnectionsAsync(string userId);
    Task<bool> IsUserOnlineAsync(string userId);
}

public class RedisConnectionTracker : IConnectionTracker
{
    private readonly IDistributedCache _cache;
    private readonly TimeSpan _connectionTimeout = TimeSpan.FromHours(2);

    public RedisConnectionTracker(IDistributedCache cache)
    {
        _cache = cache;
    }

    public async Task AddConnectionAsync(string userId, string connectionId)
    {
        var key = $"connections:{userId}";
        var connections = await GetConnectionsAsync(userId);
        connections.Add(connectionId);
        
        await _cache.SetStringAsync(key, 
            JsonSerializer.Serialize(connections),
            new DistributedCacheEntryOptions
            {
                SlidingExpiration = _connectionTimeout
            });
    }

    public async Task RemoveConnectionAsync(string userId, string connectionId)
    {
        var key = $"connections:{userId}";
        var connections = await GetConnectionsAsync(userId);
        connections.Remove(connectionId);

        if (connections.Count == 0)
        {
            await _cache.RemoveAsync(key);
        }
        else
        {
            await _cache.SetStringAsync(key, 
                JsonSerializer.Serialize(connections),
                new DistributedCacheEntryOptions
                {
                    SlidingExpiration = _connectionTimeout
                });
        }
    }

    public async Task<IReadOnlyList<string>> GetUserConnectionsAsync(string userId)
    {
        return await GetConnectionsAsync(userId);
    }

    public async Task<bool> IsUserOnlineAsync(string userId)
    {
        var connections = await GetConnectionsAsync(userId);
        return connections.Count > 0;
    }

    private async Task<List<string>> GetConnectionsAsync(string userId)
    {
        var key = $"connections:{userId}";
        var json = await _cache.GetStringAsync(key);
        
        return string.IsNullOrEmpty(json) 
            ? new List<string>() 
            : JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>();
    }
}

// Scale-out configuration
builder.Services.AddSignalR()
    .AddStackExchangeRedis(options =>
    {
        options.Configuration.ConnectionString = "redis:6379";
        options.Configuration.AbortOnConnectFail = false;
    })
    .AddMessagePackProtocol(); // Binary protocol for better performance

// Sticky sessions are NOT needed with Redis backplane
// Load balancer can use round-robin
```

## Anti-Patterns

```javascript
// ❌ BAD: Creating new connection on every page
const connection = new signalR.HubConnectionBuilder()
    .withUrl('/hubs/notifications')
    .build();
await connection.start(); // Creates new connection every time!

// ✅ GOOD: Reuse connections across pages
// Use the SignalRClient class shown in Pattern 2
```

```csharp
// ❌ BAD: Calling clients without error handling
public async Task SendNotification(string userId, string message)
{
    await _hubContext.Clients.Group($"user:{userId}")
        .ReceiveNotification(message); // May throw if user not connected
}

// ✅ GOOD: Handle errors gracefully
public async Task SendNotification(string userId, string message)
{
    try
    {
        await _hubContext.Clients.Group($"user:{userId}")
            .ReceiveNotification(message);
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Failed to send notification to {UserId}", userId);
        // Queue for later delivery or mark as pending
    }
}

// ❌ BAD: Storing hub context in static/singleton
public static class BadNotificationService
{
    public static IHubContext<NotificationHub> HubContext { get; set; } = null!;
}

// ✅ GOOD: Inject IHubContext where needed
public class GoodNotificationService
{
    private readonly IHubContext<NotificationHub> _hubContext;
    
    public GoodNotificationService(IHubContext<NotificationHub> hubContext)
    {
        _hubContext = hubContext;
    }
}

// ❌ BAD: Blocking in hub methods
public string GetData()
{
    var result = _service.GetDataAsync().Result; // Deadlock risk!
    return result;
}

// ✅ GOOD: Use async throughout
public async Task<string> GetDataAsync()
{
    return await _service.GetDataAsync();
}

// ❌ BAD: Not validating group membership
public async Task JoinGroup(string groupName)
{
    await Groups.AddToGroupAsync(Context.ConnectionId, groupName);
    // Anyone can join any group!
}

// ✅ GOOD: Validate before adding to group
public async Task JoinGroup(string groupName)
{
    if (!await CanJoinGroup(groupName))
    {
        throw new HubException("Access denied");
    }
    
    await Groups.AddToGroupAsync(Context.ConnectionId, groupName);
}

// ❌ BAD: Trusting client-provided user ID
public async Task SendMessage(string userId, string message)
{
    // Client could impersonate any user!
    await Clients.Group($"user:{userId}").ReceiveMessage(message);
}

// ✅ GOOD: Use authenticated identity from Context
public async Task SendMessage(string targetUserId, string message)
{
    var senderId = Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (string.IsNullOrEmpty(senderId))
    {
        throw new HubException("Not authenticated");
    }
    
    // Validate sender can message target
    if (!await CanMessageUser(senderId, targetUserId))
    {
        throw new HubException("Not authorized");
    }
    
    await Clients.Group($"user:{targetUserId}").ReceiveMessage(new {
        From = senderId,
        Message = message,
        Timestamp = DateTime.UtcNow
    });
}

// ❌ BAD: Broadcasting to all clients without filtering
public async Task BroadcastUpdate(string data)
{
    await Clients.All.ReceiveUpdate(data); // All connected clients!
}

// ✅ GOOD: Target specific groups or use authorization
public async Task BroadcastToAuthorized(string data)
{
    // Only send to users with specific role or permission
    await Clients.Group("admins").ReceiveUpdate(data);
}
```

## References

- [SignalR in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction)
- [SignalR HubContext](https://learn.microsoft.com/en-us/aspnet/core/signalr/hubcontext)
- [SignalR Scale-Out with Redis](https://learn.microsoft.com/en-us/aspnet/core/signalr/redis-backplane)
- [SignalR Security](https://learn.microsoft.com/en-us/aspnet/core/signalr/security)
- [SignalR JavaScript Client](https://learn.microsoft.com/en-us/aspnet/core/signalr/javascript-client)
