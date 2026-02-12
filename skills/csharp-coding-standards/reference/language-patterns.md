# Language Patterns

## Language Patterns

### Records for Immutable Data (C# 9+)

Use `record` types for DTOs, messages, events, and domain entities.

```csharp
// Simple immutable DTO
public record CustomerDto(string Id, string Name, string Email);

// Record with validation in constructor
public record EmailAddress
{
    public string Value { get; init; }

    public EmailAddress(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || !value.Contains('@'))
            throw new ArgumentException("Invalid email address", nameof(value));

        Value = value;
    }
}

// Record with computed properties
public record Order(string Id, decimal Subtotal, decimal Tax)
{
    public decimal Total => Subtotal + Tax;
}

// Records with collections - use IReadOnlyList
public record ShoppingCart(
    string CartId,
    string CustomerId,
    IReadOnlyList<CartItem> Items
)
{
    public decimal Total => Items.Sum(item => item.Price * item.Quantity);
}
```

**When to use `record class` vs `record struct`:**
- `record class` (default): Reference types, use for entities, aggregates, DTOs with multiple properties
- `record struct`: Value types, use for value objects (see next section)

---

### Value Objects as readonly record struct

Value objects should **always be `readonly record struct`** for performance and value semantics.

```csharp
// Single-value object
public readonly record struct OrderId(string Value)
{
    public OrderId(string value) : this(
        !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new ArgumentException("OrderId cannot be empty", nameof(value)))
    {
    }

    public override string ToString() => Value;

    // NO implicit conversions - defeats type safety!
    // Access inner value explicitly: orderId.Value
}

// Multi-value object
public readonly record struct Money(decimal Amount, string Currency)
{
    public Money(decimal amount, string currency) : this(
        amount >= 0 ? amount : throw new ArgumentException("Amount cannot be negative", nameof(amount)),
        ValidateCurrency(currency))
    {
    }

    private static string ValidateCurrency(string currency)
    {
        if (string.IsNullOrWhiteSpace(currency) || currency.Length != 3)
            throw new ArgumentException("Currency must be a 3-letter code", nameof(currency));
        return currency.ToUpperInvariant();
    }

    public Money Add(Money other)
    {
        if (Currency != other.Currency)
            throw new InvalidOperationException($"Cannot add {Currency} to {other.Currency}");

        return new Money(Amount + other.Amount, Currency);
    }

    public override string ToString() => $"{Amount:N2} {Currency}";
}

// Complex value object with factory pattern
public readonly record struct PhoneNumber
{
    public string Value { get; }

    private PhoneNumber(string value) => Value = value;

    public static Result<PhoneNumber, string> Create(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return Result<PhoneNumber, string>.Failure("Phone number cannot be empty");

        // Normalize: remove all non-digits
        var digits = new string(input.Where(char.IsDigit).ToArray());

        if (digits.Length < 10 || digits.Length > 15)
            return Result<PhoneNumber, string>.Failure("Phone number must be 10-15 digits");

        return Result<PhoneNumber, string>.Success(new PhoneNumber(digits));
    }

    public override string ToString() => Value;
}

// Percentage value object with range validation
public readonly record struct Percentage
{
    private readonly decimal _value;

    public decimal Value => _value;

    public Percentage(decimal value)
    {
        if (value < 0 || value > 100)
            throw new ArgumentOutOfRangeException(nameof(value), "Percentage must be between 0 and 100");
        _value = value;
    }

    public decimal AsDecimal() => _value / 100m;

    public static Percentage FromDecimal(decimal decimalValue)
    {
        if (decimalValue < 0 || decimalValue > 1)
            throw new ArgumentOutOfRangeException(nameof(decimalValue), "Decimal must be between 0 and 1");
        return new Percentage(decimalValue * 100);
    }

    public override string ToString() => $"{_value}%";
}

// Strongly-typed ID
public readonly record struct CustomerId(Guid Value)
{
    public static CustomerId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}

// Quantity with units
public readonly record struct Quantity(int Value, string Unit)
{
    public Quantity(int value, string unit) : this(
        value >= 0 ? value : throw new ArgumentException("Quantity cannot be negative"),
        !string.IsNullOrWhiteSpace(unit) ? unit : throw new ArgumentException("Unit cannot be empty"))
    {
    }

    public override string ToString() => $"{Value} {Unit}";
}
```

**Why `readonly record struct` for value objects:**
- **Value semantics**: Equality based on content, not reference
- **Stack allocation**: Better performance, no GC pressure
- **Immutability**: `readonly` prevents accidental mutation
- **Pattern matching**: Works seamlessly with switch expressions

**CRITICAL: NO implicit conversions.** Implicit operators defeat the purpose of value objects by allowing silent type coercion:

```csharp
// WRONG - defeats compile-time safety:
public readonly record struct UserId(Guid Value)
{
    public static implicit operator UserId(Guid value) => new(value);  // NO!
    public static implicit operator Guid(UserId value) => value.Value; // NO!
}

// With implicit operators, this compiles silently:
void ProcessUser(UserId userId) { }
ProcessUser(Guid.NewGuid());  // Oops - meant to pass PostId

// CORRECT - all conversions explicit:
public readonly record struct UserId(Guid Value)
{
    public static UserId New() => new(Guid.NewGuid());
    // No implicit operators
    // Create: new UserId(guid) or UserId.New()
    // Extract: userId.Value
}
```

Explicit conversions force every boundary crossing to be visible:

```csharp
// API boundary - explicit conversion IN
var userId = new UserId(request.UserId);  // Validates on entry

// Database boundary - explicit conversion OUT
await _db.ExecuteAsync(sql, new { UserId = userId.Value });
```

---

### Pattern Matching (C# 8-12)

Leverage modern pattern matching for cleaner, more expressive code.

```csharp
// Switch expressions with value objects
public string GetPaymentMethodDescription(PaymentMethod payment) => payment switch
{
    { Type: PaymentType.CreditCard, Last4: var last4 } => $"Credit card ending in {last4}",
    { Type: PaymentType.BankTransfer, AccountNumber: var account } => $"Bank transfer from {account}",
    { Type: PaymentType.Cash } => "Cash payment",
    _ => "Unknown payment method"
};

// Property patterns
public decimal CalculateDiscount(Order order) => order switch
{
    { Total: > 1000m } => order.Total * 0.15m,
    { Total: > 500m } => order.Total * 0.10m,
    { Total: > 100m } => order.Total * 0.05m,
    _ => 0m
};

// Relational and logical patterns
public string ClassifyTemperature(int temp) => temp switch
{
    < 0 => "Freezing",
    >= 0 and < 10 => "Cold",
    >= 10 and < 20 => "Cool",
    >= 20 and < 30 => "Warm",
    >= 30 => "Hot",
    _ => throw new ArgumentOutOfRangeException(nameof(temp))
};

// List patterns (C# 11+)
public bool IsValidSequence(int[] numbers) => numbers switch
{
    [] => false,                                      // Empty
    [_] => true,                                      // Single element
    [var first, .., var last] when first < last => true,  // First < last
    _ => false
};

// Type patterns with null checks
public string FormatValue(object? value) => value switch
{
    null => "null",
    string s => $"\"{s}\"",
    int i => i.ToString(),
    double d => d.ToString("F2"),
    DateTime dt => dt.ToString("yyyy-MM-dd"),
    Money m => m.ToString(),
    IEnumerable<object> collection => $"[{string.Join(", ", collection)}]",
    _ => value.ToString() ?? "unknown"
};

// Combining patterns for complex logic
public record OrderState(bool IsPaid, bool IsShipped, bool IsCancelled);

public string GetOrderStatus(OrderState state) => state switch
{
    { IsCancelled: true } => "Cancelled",
    { IsPaid: true, IsShipped: true } => "Delivered",
    { IsPaid: true, IsShipped: false } => "Processing",
    { IsPaid: false } => "Awaiting Payment",
    _ => "Unknown"
};

// Pattern matching with value objects
public decimal CalculateShipping(Money total, Country destination) => (total, destination) switch
{
    ({ Amount: > 100m }, _) => 0m,                    // Free shipping over $100
    (_, { Code: "US" or "CA" }) => 5m,                // North America
    (_, { Code: "GB" or "FR" or "DE" }) => 10m,       // Europe
    _ => 25m                                           // International
};
```

---

### Nullable Reference Types (C# 8+)

Enable nullable reference types in your project and handle nulls explicitly.

```csharp
// In .csproj
<PropertyGroup>
    <Nullable>enable</Nullable>
</PropertyGroup>

// Explicit nullability
public class UserService
{
    // Non-nullable by default
    public string GetUserName(User user) => user.Name;

    // Explicitly nullable return
    public string? FindUserName(string userId)
    {
        var user = _repository.Find(userId);
        return user?.Name;  // Returns null if user not found
    }

    // Null-forgiving operator (use sparingly!)
    public string GetRequiredConfigValue(string key)
    {
        var value = Configuration[key];
        return value!;  // Only if you're CERTAIN it's not null
    }

    // Nullable value objects
    public Money? GetAccountBalance(string accountId)
    {
        var account = _repository.Find(accountId);
        return account?.Balance;
    }
}

// Pattern matching with null checks
public decimal GetDiscount(Customer? customer) => customer switch
{
    null => 0m,
    { IsVip: true } => 0.20m,
    { OrderCount: > 10 } => 0.10m,
    _ => 0.05m
};

// Null-coalescing patterns
public string GetDisplayName(User? user) =>
    user?.PreferredName ?? user?.Email ?? "Guest";

// Guard clauses with ArgumentNullException.ThrowIfNull (C# 11+)
public void ProcessOrder(Order? order)
{
    ArgumentNullException.ThrowIfNull(order);

    // order is now non-nullable in this scope
    Console.WriteLine(order.Id);
}
```

---

## Composition Over Inheritance

**Avoid abstract base classes and inheritance hierarchies.** Use composition and interfaces instead.

```csharp
// ❌ BAD: Abstract base class hierarchy
public abstract class PaymentProcessor
{
    public abstract Task<PaymentResult> ProcessAsync(Money amount);

    protected async Task<bool> ValidateAsync(Money amount)
    {
        // Shared validation logic
        return amount.Amount > 0;
    }
}

public class CreditCardProcessor : PaymentProcessor
{
    public override async Task<PaymentResult> ProcessAsync(Money amount)
    {
        await ValidateAsync(amount);
        // Process credit card...
    }
}

// ✅ GOOD: Composition with interfaces
public interface IPaymentProcessor
{
    Task<PaymentResult> ProcessAsync(Money amount, CancellationToken cancellationToken);
}

public interface IPaymentValidator
{
    Task<ValidationResult> ValidateAsync(Money amount, CancellationToken cancellationToken);
}

// Concrete implementations compose validators
public sealed class CreditCardProcessor : IPaymentProcessor
{
    private readonly IPaymentValidator _validator;
    private readonly ICreditCardGateway _gateway;

    public CreditCardProcessor(IPaymentValidator validator, ICreditCardGateway gateway)
    {
        _validator = validator;
        _gateway = gateway;
    }

    public async Task<PaymentResult> ProcessAsync(Money amount, CancellationToken cancellationToken)
    {
        var validation = await _validator.ValidateAsync(amount, cancellationToken);
        if (!validation.IsValid)
            return PaymentResult.Failed(validation.Error);

        return await _gateway.ChargeAsync(amount, cancellationToken);
    }
}

// ✅ GOOD: Static helper classes for shared logic (no inheritance)
public static class PaymentValidation
{
    public static ValidationResult ValidateAmount(Money amount)
    {
        if (amount.Amount <= 0)
            return ValidationResult.Invalid("Amount must be positive");

        if (amount.Amount > 10000m)
            return ValidationResult.Invalid("Amount exceeds maximum");

        return ValidationResult.Valid();
    }
}

// ✅ GOOD: Records for modeling variants (not inheritance)
public enum PaymentType { CreditCard, BankTransfer, Cash }

public record PaymentMethod
{
    public PaymentType Type { get; init; }
    public string? Last4 { get; init; }           // For credit cards
    public string? AccountNumber { get; init; }    // For bank transfers

    public static PaymentMethod CreditCard(string last4) => new()
    {
        Type = PaymentType.CreditCard,
        Last4 = last4
    };

    public static PaymentMethod BankTransfer(string accountNumber) => new()
    {
        Type = PaymentType.BankTransfer,
        AccountNumber = accountNumber
    };

    public static PaymentMethod Cash() => new() { Type = PaymentType.Cash };
}
```

**When inheritance is acceptable:**
- Framework requirements (e.g., `ControllerBase` in ASP.NET Core)
- Library integration (e.g., custom exceptions inheriting from `Exception`)
- **These should be rare cases in your application code**

---
