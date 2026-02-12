# Error Handling

## Error Handling

### Result Type Pattern (Railway-Oriented Programming)

For expected errors, use a `Result<T, TError>` type instead of exceptions.

```csharp
// Simple Result type as readonly record struct
public readonly record struct Result<TValue, TError>
{
    private readonly TValue? _value;
    private readonly TError? _error;
    private readonly bool _isSuccess;

    private Result(TValue value)
    {
        _value = value;
        _error = default;
        _isSuccess = true;
    }

    private Result(TError error)
    {
        _value = default;
        _error = error;
        _isSuccess = false;
    }

    public bool IsSuccess => _isSuccess;
    public bool IsFailure => !_isSuccess;

    public TValue Value => _isSuccess
        ? _value!
        : throw new InvalidOperationException("Cannot access Value of a failed result");

    public TError Error => !_isSuccess
        ? _error!
        : throw new InvalidOperationException("Cannot access Error of a successful result");

    public static Result<TValue, TError> Success(TValue value) => new(value);
    public static Result<TValue, TError> Failure(TError error) => new(error);

    public Result<TOut, TError> Map<TOut>(Func<TValue, TOut> mapper)
        => _isSuccess
            ? Result<TOut, TError>.Success(mapper(_value!))
            : Result<TOut, TError>.Failure(_error!);

    public Result<TOut, TError> Bind<TOut>(Func<TValue, Result<TOut, TError>> binder)
        => _isSuccess ? binder(_value!) : Result<TOut, TError>.Failure(_error!);

    public TValue GetValueOr(TValue defaultValue)
        => _isSuccess ? _value! : defaultValue;

    public TResult Match<TResult>(
        Func<TValue, TResult> onSuccess,
        Func<TError, TResult> onFailure)
        => _isSuccess ? onSuccess(_value!) : onFailure(_error!);
}

// Error type as readonly record struct
public readonly record struct OrderError(string Code, string Message);

// Usage example
public sealed class OrderService(IOrderRepository repository)
{
    public async Task<Result<Order, OrderError>> CreateOrderAsync(
        CreateOrderRequest request,
        CancellationToken cancellationToken)
    {
        // Validate
        var validationResult = ValidateRequest(request);
        if (validationResult.IsFailure)
            return Result<Order, OrderError>.Failure(validationResult.Error);

        // Check inventory
        var inventoryResult = await CheckInventoryAsync(request.Items, cancellationToken);
        if (inventoryResult.IsFailure)
            return Result<Order, OrderError>.Failure(inventoryResult.Error);

        // Create order
        var order = new Order(
            OrderId.New(),
            new CustomerId(request.CustomerId),
            request.Items);

        await repository.SaveAsync(order, cancellationToken);

        return Result<Order, OrderError>.Success(order);
    }

    // Pattern matching on Result
    public IActionResult MapToActionResult(Result<Order, OrderError> result)
    {
        return result.Match(
            onSuccess: order => new OkObjectResult(order),
            onFailure: error => error.Code switch
            {
                "VALIDATION_ERROR" => new BadRequestObjectResult(error.Message),
                "INSUFFICIENT_INVENTORY" => new ConflictObjectResult(error.Message),
                "NOT_FOUND" => new NotFoundObjectResult(error.Message),
                _ => new ObjectResult(error.Message) { StatusCode = 500 }
            }
        );
    }
}
```

**When to use Result vs Exceptions:**
- **Use Result**: Expected errors (validation, business rules, not found)
- **Use Exceptions**: Unexpected errors (network failures, system errors, programming bugs)

---
