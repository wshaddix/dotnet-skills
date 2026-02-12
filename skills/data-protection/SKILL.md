---
name: data-protection
description: ASP.NET Core Data Protection API patterns for encryption, key management, and secure data handling in web applications. Use when protecting sensitive data at rest or in transit, managing encryption keys in ASP.NET Core applications, or implementing secure token generation and validation.
---

## Rationale

Protecting sensitive data is critical for security compliance and user privacy. The ASP.NET Core Data Protection API provides a secure, easy-to-use framework for encryption, key management, and data protection. Without proper patterns, applications risk data exposure, key management failures, and compliance violations. These patterns ensure secure, maintainable data protection practices.

## Patterns

### Pattern 1: Data Protection Configuration

Configure Data Protection with proper key storage and application isolation.

```csharp
// Program.cs - Basic configuration
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp") // Critical for multi-app environments
    .PersistKeysToFileSystem(new DirectoryInfo(@"\shared\keys"))
    .ProtectKeysWithDpapi(); // Windows only

// Cross-platform key protection
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp")
    .PersistKeysToFileSystem(new DirectoryInfo(@"/shared/keys"))
    .ProtectKeysWithCertificate(
        new X509Certificate2("/certs/dataprotection.pfx", "password"));

// Azure Blob Storage for key persistence (production)
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp")
    .PersistKeysToAzureBlobStorage(blobUri)
    .ProtectKeysWithAzureKeyVaultKey(keyVaultKeyId);

// Redis for key storage in containerized environments
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp")
    .PersistKeysToStackExchangeRedis(connection, "DataProtection-Keys")
    .ProtectKeysWithCertificate(certificate);
```

### Pattern 2: Protecting Sensitive Data at Rest

Use Data Protection to encrypt sensitive data before storing in databases.

```csharp
public interface IDataProtectorService
{
    string Protect(string plainText);
    string? Unprotect(string protectedText);
    byte[] Protect(byte[] plainData);
    byte[]? Unprotect(byte[] protectedData);
}

public class DataProtectorService : IDataProtectorService
{
    private readonly IDataProtector _protector;
    private readonly ILogger<DataProtectorService> _logger;

    public DataProtectorService(
        IDataProtectionProvider dataProtectionProvider,
        ILogger<DataProtectorService> logger)
    {
        // Create purpose-specific protector
        _protector = dataProtectionProvider.CreateProtector("MyApp.SensitiveData.v1");
        _logger = logger;
    }

    public string Protect(string plainText)
    {
        if (string.IsNullOrEmpty(plainText))
            return plainText;

        try
        {
            return _protector.Protect(plainText);
        }
        catch (CryptographicException ex)
        {
            _logger.LogError(ex, "Failed to protect data");
            throw;
        }
    }

    public string? Unprotect(string protectedText)
    {
        if (string.IsNullOrEmpty(protectedText))
            return protectedText;

        try
        {
            return _protector.Unprotect(protectedText);
        }
        catch (CryptographicException ex)
        {
            _logger.LogWarning(ex, "Failed to unprotect data - may be corrupted or from different key");
            return null;
        }
    }

    public byte[] Protect(byte[] plainData)
    {
        ArgumentNullException.ThrowIfNull(plainData);
        return _protector.Protect(plainData);
    }

    public byte[]? Unprotect(byte[] protectedData)
    {
        ArgumentNullException.ThrowIfNull(protectedData);
        
        try
        {
            return _protector.Unprotect(protectedData);
        }
        catch (CryptographicException ex)
        {
            _logger.LogWarning(ex, "Failed to unprotect binary data");
            return null;
        }
    }
}

// Entity with encrypted fields
public class PaymentMethod
{
    public Guid Id { get; set; }
    public required string UserId { get; set; }
    
    // Store encrypted card number
    public required string EncryptedCardNumber { get; set; }
    
    // Last 4 digits stored in clear for display
    public required string CardLastFourDigits { get; set; }
    
    public required string EncryptedExpirationDate { get; set; }
    public required string CardType { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    
    [NotMapped]
    public string? CardNumber { get; set; }
    
    [NotMapped]
    public string? ExpirationDate { get; set; }
}

// Repository with encryption/decryption
public class PaymentMethodRepository
{
    private readonly ApplicationDbContext _dbContext;
    private readonly IDataProtectorService _protector;

    public PaymentMethodRepository(
        ApplicationDbContext dbContext,
        IDataProtectorService protector)
    {
        _dbContext = dbContext;
        _protector = protector;
    }

    public async Task<PaymentMethod> AddAsync(PaymentMethod paymentMethod)
    {
        // Encrypt sensitive fields before saving
        paymentMethod.EncryptedCardNumber = _protector.Protect(paymentMethod.CardNumber!);
        paymentMethod.EncryptedExpirationDate = _protector.Protect(paymentMethod.ExpirationDate!);
        
        // Store last 4 digits for display
        paymentMethod.CardLastFourDigits = paymentMethod.CardNumber![^4..];
        
        // Clear plain text fields (they're NotMapped anyway)
        paymentMethod.CardNumber = null;
        paymentMethod.ExpirationDate = null;
        
        _dbContext.PaymentMethods.Add(paymentMethod);
        await _dbContext.SaveChangesAsync();
        
        return paymentMethod;
    }

    public async Task<PaymentMethod?> GetByIdAsync(Guid id)
    {
        var paymentMethod = await _dbContext.PaymentMethods
            .FirstOrDefaultAsync(p => p.Id == id);

        if (paymentMethod != null)
        {
            // Decrypt for use
            paymentMethod.CardNumber = _protector.Unprotect(paymentMethod.EncryptedCardNumber);
            paymentMethod.ExpirationDate = _protector.Unprotect(paymentMethod.EncryptedExpirationDate);
        }

        return paymentMethod;
    }

    public async Task<List<PaymentMethod>> GetByUserIdAsync(string userId)
    {
        // Return without decrypted data for listing
        return await _dbContext.PaymentMethods
            .AsNoTracking()
            .Where(p => p.UserId == userId)
            .Select(p => new PaymentMethod
            {
                Id = p.Id,
                UserId = p.UserId,
                CardLastFourDigits = p.CardLastFourDigits,
                CardType = p.CardType,
                CreatedAt = p.CreatedAt
                // Don't include encrypted fields or decrypted data
            })
            .ToListAsync();
    }
}
```

### Pattern 3: Time-Limited Protection

Create tokens that expire after a set time using time-limited data protectors.

```csharp
public class TokenService
{
    private readonly ITimeLimitedDataProtector _protector;
    private readonly ILogger<TokenService> _logger;

    public TokenService(IDataProtectionProvider dataProtectionProvider, ILogger<TokenService> logger)
    {
        var baseProtector = dataProtectionProvider.CreateProtector("MyApp.TimeLimitedTokens");
        _protector = baseProtector.ToTimeLimitedDataProtector();
        _logger = logger;
    }

    public string GenerateToken(string purpose, string userId, TimeSpan lifetime)
    {
        var payload = JsonSerializer.Serialize(new TokenPayload
        {
            Purpose = purpose,
            UserId = userId,
            IssuedAt = DateTimeOffset.UtcNow
        });

        return _protector.Protect(payload, lifetime);
    }

    public TokenPayload? ValidateToken(string token, string expectedPurpose)
    {
        try
        {
            var payload = _protector.Unprotect(token, out var expiration);
            var data = JsonSerializer.Deserialize<TokenPayload>(payload);

            if (data?.Purpose != expectedPurpose)
            {
                _logger.LogWarning("Token purpose mismatch: expected {Expected}, got {Actual}",
                    expectedPurpose, data?.Purpose);
                return null;
            }

            _logger.LogDebug("Token validated, expires at {Expiration}", expiration);
            return data;
        }
        catch (CryptographicException ex)
        {
            _logger.LogWarning(ex, "Token validation failed");
            return null;
        }
    }

    public string GeneratePasswordResetToken(string userId, string email)
    {
        // 1 hour expiration
        return GenerateToken("password-reset", $"{userId}:{email}", TimeSpan.FromHours(1));
    }

    public string GenerateEmailConfirmationToken(string userId, string email)
    {
        // 24 hour expiration
        return GenerateToken("email-confirmation", $"{userId}:{email}", TimeSpan.FromHours(24));
    }

    public (string? UserId, string? Email)? ValidatePasswordResetToken(string token)
    {
        var payload = ValidateToken(token, "password-reset");
        if (payload == null) return null;

        var parts = payload.UserId.Split(':');
        return parts.Length == 2 ? (parts[0], parts[1]) : null;
    }
}

public class TokenPayload
{
    public required string Purpose { get; set; }
    public required string UserId { get; set; }
    public DateTimeOffset IssuedAt { get; set; }
}

// Usage in Razor Page
public class ResetPasswordModel : PageModel
{
    private readonly TokenService _tokenService;
    private readonly IUserService _userService;

    [BindProperty]
    public ResetPasswordInput Input { get; set; } = new();

    public string? ErrorMessage { get; set; }

    public async Task<IActionResult> OnGetAsync(string token)
    {
        var validation = _tokenService.ValidatePasswordResetToken(token);
        
        if (validation == null)
        {
            ErrorMessage = "Invalid or expired reset token";
            return Page();
        }

        Input.Token = token;
        return Page();
    }

    public async Task<IActionResult> OnPostAsync()
    {
        var validation = _tokenService.ValidatePasswordResetToken(Input.Token);
        
        if (validation == null)
        {
            ErrorMessage = "Invalid or expired reset token";
            return Page();
        }

        var (userId, email) = validation.Value;
        await _userService.ResetPasswordAsync(userId, Input.NewPassword);
        
        return RedirectToPage("/Account/ResetPasswordConfirmation");
    }
}
```

### Pattern 4: Key Rotation and Management

Implement proper key rotation strategies without breaking existing protected data.

```csharp
// Custom key management with rotation policies
public class KeyRotationConfiguration
{
    public void Configure(DataProtectionOptions options)
    {
        options.ApplicationDiscriminator = "MyApp.Production";
    }
}

// Key storage with versioning
public class VersionedKeyManager
{
    private readonly ILogger<VersionedKeyManager> _logger;

    public VersionedKeyManager(ILogger<VersionedKeyManager> logger)
    {
        _logger = logger;
    }

    public void RotateKeys(IDataProtectionProvider provider)
    {
        // Data Protection automatically handles key rotation
        // Keys are valid for 90 days by default, with 7 day activation delay
        
        // Log current key status
        var keyManager = provider.GetService<IKeyManager>();
        if (keyManager != null)
        {
            var allKeys = keyManager.GetAllKeys();
            
            _logger.LogInformation("Current keys: {KeyCount}", allKeys.Count());
            
            foreach (var key in allKeys)
            {
                _logger.LogDebug(
                    "Key {KeyId}: Created {Created}, Activation {Activation}, Expiration {Expiration}",
                    key.KeyId,
                    key.CreationDate,
                    key.ActivationDate,
                    key.ExpirationDate);
            }
        }
    }
}

// Configuration for production
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp")
    .SetDefaultKeyLifetime(TimeSpan.FromDays(90)) // Rotate every 90 days
    .PersistKeysToFileSystem(new DirectoryInfo(@"/shared/keys"))
    .ProtectKeysWithCertificate(LoadCertificate())
    .DisableAutomaticKeyGeneration(); // For controlled rotation environments

// Certificate loading
X509Certificate2 LoadCertificate()
{
    // From file
    return new X509Certificate2("dataprotection.pfx", "password");
    
    // Or from store
    using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
    store.Open(OpenFlags.ReadOnly);
    var certs = store.Certificates.Find(
        X509FindType.FindByThumbprint, 
        "thumbprint", 
        validOnly: false);
    return certs[0];
}
```

### Pattern 5: Protected Session Data

Secure sensitive session data with Data Protection.

```csharp
public class ProtectedSessionService
{
    private readonly IDataProtector _protector;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public ProtectedSessionService(
        IDataProtectionProvider dataProtectionProvider,
        IHttpContextAccessor httpContextAccessor)
    {
        _protector = dataProtectionProvider.CreateProtector("MyApp.SessionData");
        _httpContextAccessor = httpContextAccessor;
    }

    public void SetProtected<T>(string key, T value)
    {
        var session = _httpContextAccessor.HttpContext?.Session;
        if (session == null) return;

        var json = JsonSerializer.Serialize(value);
        var protectedData = _protector.Protect(json);
        session.SetString($"protected:{key}", protectedData);
    }

    public T? GetProtected<T>(string key)
    {
        var session = _httpContextAccessor.HttpContext?.Session;
        if (session == null) return default;

        var protectedData = session.GetString($"protected:{key}");
        if (string.IsNullOrEmpty(protectedData)) return default;

        try
        {
            var json = _protector.Unprotect(protectedData);
            return JsonSerializer.Deserialize<T>(json);
        }
        catch (CryptographicException)
        {
            // Data was tampered with or keys changed
            session.Remove($"protected:{key}");
            return default;
        }
    }

    public void RemoveProtected(string key)
    {
        _httpContextAccessor.HttpContext?.Session.Remove($"protected:{key}");
    }
}

// Usage in Razor Page
public class CheckoutModel : PageModel
{
    private readonly ProtectedSessionService _session;

    public async Task<IActionResult> OnPostAsync()
    {
        // Store sensitive checkout data securely
        _session.SetProtected("checkout:payment-intent", new PaymentIntentData
        {
            IntentId = paymentIntent.Id,
            Amount = Input.Amount,
            Currency = Input.Currency,
            CustomerId = Input.CustomerId
        });

        // Later, retrieve it
        var intentData = _session.GetProtected<PaymentIntentData>("checkout:payment-intent");
        
        // Clear after completion
        _session.RemoveProtected("checkout:payment-intent");
    }
}
```

## Anti-Patterns

```csharp
// ❌ BAD: Hard-coded encryption keys
public class BadEncryptionService
{
    private readonly byte[] _key = Convert.FromBase64String("hardcoded-key-here");
    
    public string Encrypt(string data)
    {
        using var aes = Aes.Create();
        aes.Key = _key; // Never do this!
        // ...
    }
}

// ✅ GOOD: Use Data Protection
public class GoodEncryptionService
{
    private readonly IDataProtector _protector;
    
    public GoodEncryptionService(IDataProtectionProvider provider)
    {
        _protector = provider.CreateProtector("MyApp.Data");
    }
    
    public string Encrypt(string data) => _protector.Protect(data);
}

// ❌ BAD: Not setting application name
builder.Services.AddDataProtection();
// Keys may conflict with other apps on the same server!

// ✅ GOOD: Always set application discriminator
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp.Production");

// ❌ BAD: Ignoring key storage in production
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo("keys"));
// Keys lost on container restart!

// ✅ GOOD: Persistent key storage
builder.Services.AddDataProtection()
    .PersistKeysToAzureBlobStorage(blobUri)
    .ProtectKeysWithAzureKeyVaultKey(keyId);

// ❌ BAD: Exposing protected data format
public string ProtectUserId(string userId)
{
    return $"protected:{userId}"; // Not actually protected!
}

// ✅ GOOD: Use actual protection
public string ProtectUserId(string userId)
{
    return _protector.Protect(userId); // Opaque, encrypted token
}

// ❌ BAD: Swallowing all cryptographic exceptions
public string? Unprotect(string data)
{
    try
    {
        return _protector.Unprotect(data);
    }
    catch (Exception) // Too broad!
    {
        return null;
    }
}

// ✅ GOOD: Handle specific exceptions appropriately
public string? Unprotect(string data)
{
    try
    {
        return _protector.Unprotect(data);
    }
    catch (CryptographicException ex)
    {
        _logger.LogWarning(ex, "Data unprotection failed");
        return null;
    }
}

// ❌ BAD: Protecting already encrypted data
public string DoubleProtect(string data)
{
    var encrypted = _aes.Encrypt(data);
    return _protector.Protect(encrypted); // Unnecessary overhead!
}

// ✅ GOOD: Use Data Protection alone
public string Protect(string data)
{
    return _protector.Protect(data);
}

// ❌ BAD: No key backup strategy
// Keys stored in single location with no backup

// ✅ GOOD: Implement key backup
public async Task BackupKeysAsync()
{
    var keyDirectory = new DirectoryInfo("/shared/keys");
    var keys = keyDirectory.GetFiles("*.xml");
    
    foreach (var key in keys)
    {
        await UploadToBackupStorageAsync(key);
    }
}

// ❌ BAD: Sharing keys between different applications
// App1 and App2 both use same key path

// ✅ GOOD: Application-specific keys
// App1: .SetApplicationName("MyApp.Web")
// App2: .SetApplicationName("MyApp.Api")
```

## References

- [ASP.NET Core Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/)
- [Data Protection Configuration](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/configuration/)
- [Key Storage Providers](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-storage-providers)
- [Key Encryption at Rest](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-encryption-at-rest)
- [Time-Limited Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/consumer-apis/limited-lifetime-payloads)
