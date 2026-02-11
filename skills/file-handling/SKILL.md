---
name: file-handling
description: File uploads, streaming, storage abstractions, and secure file handling patterns for ASP.NET Core Razor Pages applications.
tags: [aspnetcore, file-upload, streaming, storage, razor-pages, i-form-file]
---

## Rationale

File handling is a common requirement but presents significant security and scalability challenges. Improper implementation can lead to security vulnerabilities (path traversal, malicious uploads), memory exhaustion, and storage inefficiencies. These patterns provide secure, performant, and maintainable approaches to file operations in Razor Pages.

## Patterns

### Pattern 1: Secure File Upload Validation

Implement comprehensive validation for file uploads including type, size, and content verification.

```csharp
public class FileUploadValidator
{
    private readonly long _maxFileSize;
    private readonly string[] _allowedExtensions;
    private readonly Dictionary<string, byte[]> _fileSignatures;

    public FileUploadValidator(IConfiguration configuration)
    {
        _maxFileSize = configuration.GetValue<long>("FileUpload:MaxSize", 10 * 1024 * 1024); // 10MB
        _allowedExtensions = configuration.GetSection("FileUpload:AllowedExtensions")
            .Get<string[]>() ?? new[] { ".jpg", ".jpeg", ".png", ".pdf", ".doc", ".docx" };
        
        // Magic numbers for file type validation
        _fileSignatures = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase)
        {
            [".jpg"] = new byte[] { 0xFF, 0xD8, 0xFF },
            [".jpeg"] = new byte[] { 0xFF, 0xD8, 0xFF },
            [".png"] = new byte[] { 0x89, 0x50, 0x4E, 0x47 },
            [".pdf"] = new byte[] { 0x25, 0x50, 0x44, 0x46 },
            [".docx"] = new byte[] { 0x50, 0x4B, 0x03, 0x04 }
        };
    }

    public async Task<ValidationResult> ValidateAsync(IFormFile file)
    {
        // Check file exists
        if (file == null || file.Length == 0)
        {
            return ValidationResult.Failure("No file provided");
        }

        // Check file size
        if (file.Length > _maxFileSize)
        {
            return ValidationResult.Failure(
                $"File size exceeds maximum allowed size of {_maxFileSize / 1024 / 1024}MB");
        }

        // Get and validate extension
        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!_allowedExtensions.Contains(extension))
        {
            return ValidationResult.Failure(
                $"File type '{extension}' is not allowed. Allowed types: {string.Join(", ", _allowedExtensions)}");
        }

        // Validate file signature (magic number)
        if (_fileSignatures.TryGetValue(extension, out var signature))
        {
            using var stream = file.OpenReadStream();
            var header = new byte[signature.Length];
            var bytesRead = await stream.ReadAsync(header, 0, signature.Length);
            
            if (bytesRead < signature.Length || !header.SequenceEqual(signature))
            {
                return ValidationResult.Failure(
                    "File content does not match the declared file type");
            }
        }

        // Reset stream position if needed later
        if (file is { Position: > 0 })
        {
            file.Position = 0;
        }

        return ValidationResult.Success();
    }
}

public record ValidationResult(bool IsValid, string? ErrorMessage)
{
    public static ValidationResult Success() => new(true, null);
    public static ValidationResult Failure(string error) => new(false, error);
}
```

### Pattern 2: Streaming Large Files

Handle large file uploads efficiently without loading entire files into memory.

```csharp
public class StreamingFileUploadModel : PageModel
{
    private readonly IFileStorageService _storage;
    private readonly FileUploadValidator _validator;
    private readonly ILogger<StreamingFileUploadModel> _logger;

    public StreamingFileUploadModel(
        IFileStorageService storage,
        FileUploadValidator validator,
        ILogger<StreamingFileUploadModel> logger)
    {
        _storage = storage;
        _validator = validator;
        _logger = logger;
    }

    [BindProperty]
    public string? Description { get; set; }

    public string? ErrorMessage { get; set; }
    public string? SuccessMessage { get; set; }

    // Disable form value limit for streaming
    [RequestSizeLimit(500 * 1024 * 1024)] // 500MB
    [RequestFormLimits(ValueLengthLimit = int.MaxValue, MultipartBodyLengthLimit = 500 * 1024 * 1024)]
    public async Task<IActionResult> OnPostAsync()
    {
        if (!MultipartRequestHelper.IsMultipartContentType(Request.ContentType))
        {
            ErrorMessage = "Invalid content type";
            return Page();
        }

        var boundary = MultipartRequestHelper.GetBoundary(
            MediaTypeHeaderValue.Parse(Request.ContentType),
            int.MaxValue);
        
        var reader = new MultipartReader(boundary, HttpContext.Request.Body);
        var section = await reader.ReadNextSectionAsync();

        while (section != null)
        {
            if (ContentDispositionHeaderValue.TryParse(
                section.ContentDisposition, out var contentDisposition))
            {
                if (MultipartRequestHelper.HasFileContentDisposition(contentDisposition))
                {
                    var fileName = contentDisposition.FileName.Value?.Trim('"') ?? "unnamed";
                    var safeFileName = Path.GetFileName(fileName); // Prevent path traversal
                    
                    // Validate file type by extension
                    var extension = Path.GetExtension(safeFileName).ToLowerInvariant();
                    var allowedExtensions = new[] { ".pdf", ".doc", ".docx" };
                    
                    if (!allowedExtensions.Contains(extension))
                    {
                        ErrorMessage = $"File type '{extension}' not allowed";
                        return Page();
                    }

                    // Stream directly to storage without loading into memory
                    var fileId = await _storage.UploadStreamAsync(
                        section.Body, 
                        safeFileName, 
                        section.ContentType ?? "application/octet-stream");

                    SuccessMessage = $"File uploaded successfully with ID: {fileId}";
                    
                    // Log upload
                    _logger.LogInformation(
                        "File uploaded: {FileName} with ID {FileId} by user {User}",
                        safeFileName, fileId, User.Identity?.Name ?? "anonymous");
                }
            }

            section = await reader.ReadNextSectionAsync();
        }

        return Page();
    }
}

// Helper class
public static class MultipartRequestHelper
{
    public static string GetBoundary(MediaTypeHeaderValue contentType, int lengthLimit)
    {
        var boundary = HeaderUtilities.RemoveQuotes(contentType.Boundary).Value;
        
        if (string.IsNullOrWhiteSpace(boundary))
        {
            throw new InvalidDataException("Missing content-type boundary");
        }

        if (boundary.Length > lengthLimit)
        {
            throw new InvalidDataException(
                $"Multipart boundary length limit {lengthLimit} exceeded");
        }

        return boundary;
    }

    public static bool IsMultipartContentType(string? contentType) =>
        !string.IsNullOrEmpty(contentType) && 
        contentType.Contains("multipart/", StringComparison.OrdinalIgnoreCase);

    public static bool HasFormDataContentDisposition(ContentDispositionHeaderValue contentDisposition) =>
        contentDisposition != null &&
        contentDisposition.DispositionType.Equals("form-data") &&
        string.IsNullOrEmpty(contentDisposition.FileName.Value) &&
        string.IsNullOrEmpty(contentDisposition.FileNameStar.Value);

    public static bool HasFileContentDisposition(ContentDispositionHeaderValue contentDisposition) =>
        contentDisposition != null &&
        contentDisposition.DispositionType.Equals("form-data") &&
        (!string.IsNullOrEmpty(contentDisposition.FileName.Value) ||
         !string.IsNullOrEmpty(contentDisposition.FileNameStar.Value));
}
```

### Pattern 3: Storage Abstraction

Abstract storage implementation to support multiple backends (local, Azure Blob, S3).

```csharp
// Storage abstraction interface
public interface IFileStorageService
{
    Task<string> UploadAsync(IFormFile file, CancellationToken ct = default);
    Task<string> UploadStreamAsync(Stream stream, string fileName, string contentType, CancellationToken ct = default);
    Task<Stream?> DownloadAsync(string fileId, CancellationToken ct = default);
    Task DeleteAsync(string fileId, CancellationToken ct = default);
    Task<FileMetadata?> GetMetadataAsync(string fileId, CancellationToken ct = default);
    Task<bool> ExistsAsync(string fileId, CancellationToken ct = default);
}

public record FileMetadata(
    string FileId,
    string FileName,
    string ContentType,
    long Size,
    DateTimeOffset UploadedAt,
    string UploadedBy);

// Local file system implementation
public class LocalFileStorageService : IFileStorageService
{
    private readonly string _basePath;
    private readonly ILogger<LocalFileStorageService> _logger;

    public LocalFileStorageService(IConfiguration configuration, ILogger<LocalFileStorageService> logger)
    {
        _basePath = configuration.GetValue<string>("Storage:LocalPath") ?? "uploads";
        _logger = logger;
        
        // Ensure directory exists
        Directory.CreateDirectory(_basePath);
    }

    public async Task<string> UploadAsync(IFormFile file, CancellationToken ct = default)
    {
        var fileId = Guid.NewGuid().ToString("N");
        var safeFileName = Path.GetFileName(file.FileName);
        var extension = Path.GetExtension(safeFileName);
        var storageFileName = $"{fileId}{extension}";
        
        var filePath = Path.Combine(_basePath, storageFileName);
        
        using var stream = File.Create(filePath);
        await file.CopyToAsync(stream, ct);
        
        _logger.LogInformation("File uploaded: {FileId} ({FileName})", fileId, safeFileName);
        
        return fileId;
    }

    public async Task<string> UploadStreamAsync(Stream stream, string fileName, string contentType, CancellationToken ct = default)
    {
        var fileId = Guid.NewGuid().ToString("N");
        var extension = Path.GetExtension(fileName);
        var storageFileName = $"{fileId}{extension}";
        
        var filePath = Path.Combine(_basePath, storageFileName);
        
        using var fileStream = File.Create(filePath);
        await stream.CopyToAsync(fileStream, ct);
        
        return fileId;
    }

    public Task<Stream?> DownloadAsync(string fileId, CancellationToken ct = default)
    {
        var filePath = FindFilePath(fileId);
        
        if (filePath == null)
        {
            return Task.FromResult<Stream?>(null);
        }

        return Task.FromResult<Stream?>(File.OpenRead(filePath));
    }

    public Task DeleteAsync(string fileId, CancellationToken ct = default)
    {
        var filePath = FindFilePath(fileId);
        
        if (filePath != null)
        {
            File.Delete(filePath);
            _logger.LogInformation("File deleted: {FileId}", fileId);
        }

        return Task.CompletedTask;
    }

    public Task<FileMetadata?> GetMetadataAsync(string fileId, CancellationToken ct = default)
    {
        var filePath = FindFilePath(fileId);
        
        if (filePath == null)
        {
            return Task.FromResult<FileMetadata?>(null);
        }

        var fileInfo = new FileInfo(filePath);
        var metadata = new FileMetadata(
            fileId,
            fileInfo.Name,
            MimeTypes.GetMimeType(fileInfo.Extension),
            fileInfo.Length,
            fileInfo.CreationTimeUtc,
            "unknown");

        return Task.FromResult<FileMetadata?>(metadata);
    }

    public Task<bool> ExistsAsync(string fileId, CancellationToken ct = default)
    {
        return Task.FromResult(FindFilePath(fileId) != null);
    }

    private string? FindFilePath(string fileId)
    {
        var files = Directory.GetFiles(_basePath, $"{fileId}.*");
        return files.FirstOrDefault();
    }
}

// Azure Blob Storage implementation
public class AzureBlobStorageService : IFileStorageService
{
    private readonly BlobContainerClient _containerClient;
    private readonly ILogger<AzureBlobStorageService> _logger;

    public AzureBlobStorageService(IConfiguration configuration, ILogger<AzureBlobStorageService> logger)
    {
        var connectionString = configuration.GetConnectionString("AzureStorage");
        var containerName = configuration.GetValue<string>("Storage:ContainerName") ?? "uploads";
        
        _containerClient = new BlobContainerClient(connectionString, containerName);
        _containerClient.CreateIfNotExists();
        _logger = logger;
    }

    public async Task<string> UploadAsync(IFormFile file, CancellationToken ct = default)
    {
        var fileId = Guid.NewGuid().ToString("N");
        var blobClient = _containerClient.GetBlobClient(fileId);
        
        using var stream = file.OpenReadStream();
        await blobClient.UploadAsync(stream, new BlobHttpHeaders
        {
            ContentType = file.ContentType,
            ContentDisposition = $"attachment; filename=\"{file.FileName}\""
        }, cancellationToken: ct);

        return fileId;
    }

    public async Task<string> UploadStreamAsync(Stream stream, string fileName, string contentType, CancellationToken ct = default)
    {
        var fileId = Guid.NewGuid().ToString("N");
        var blobClient = _containerClient.GetBlobClient(fileId);
        
        await blobClient.UploadAsync(stream, new BlobHttpHeaders
        {
            ContentType = contentType,
            ContentDisposition = $"attachment; filename=\"{fileName}\""
        }, cancellationToken: ct);

        return fileId;
    }

    public async Task<Stream?> DownloadAsync(string fileId, CancellationToken ct = default)
    {
        var blobClient = _containerClient.GetBlobClient(fileId);
        
        if (!await blobClient.ExistsAsync(ct))
        {
            return null;
        }

        var response = await blobClient.DownloadAsync(ct);
        return response.Value.Content;
    }

    public async Task DeleteAsync(string fileId, CancellationToken ct = default)
    {
        var blobClient = _containerClient.GetBlobClient(fileId);
        await blobClient.DeleteIfExistsAsync(cancellationToken: ct);
    }

    public async Task<FileMetadata?> GetMetadataAsync(string fileId, CancellationToken ct = default)
    {
        var blobClient = _containerClient.GetBlobClient(fileId);
        
        if (!await blobClient.ExistsAsync(ct))
        {
            return null;
        }

        var properties = await blobClient.GetPropertiesAsync(cancellationToken: ct);
        
        return new FileMetadata(
            fileId,
            properties.Value.Metadata.GetValueOrDefault("originalFileName", fileId),
            properties.Value.ContentType,
            properties.Value.ContentLength,
            properties.Value.CreatedOn,
            properties.Value.Metadata.GetValueOrDefault("uploadedBy", "unknown"));
    }

    public async Task<bool> ExistsAsync(string fileId, CancellationToken ct = default)
    {
        var blobClient = _containerClient.GetBlobClient(fileId);
        return await blobClient.ExistsAsync(ct);
    }
}
```

### Pattern 4: File Download with Security

Secure file downloads with proper content disposition and authorization.

```csharp
public class FileDownloadModel : PageModel
{
    private readonly IFileStorageService _storage;
    private readonly ILogger<FileDownloadModel> _logger;

    public FileDownloadModel(IFileStorageService storage, ILogger<FileDownloadModel> logger)
    {
        _storage = storage;
        _logger = logger;
    }

    public async Task<IActionResult> OnGetAsync(string id)
    {
        // Validate file ID format
        if (!Guid.TryParseExact(id, "N", out _))
        {
            return BadRequest("Invalid file ID");
        }

        // Get metadata
        var metadata = await _storage.GetMetadataAsync(id);
        if (metadata == null)
        {
            return NotFound();
        }

        // Check authorization
        if (!await AuthorizeDownloadAsync(metadata))
        {
            _logger.LogWarning(
                "Unauthorized download attempt for file {FileId} by user {User}",
                id, User.Identity?.Name);
            return Forbid();
        }

        // Get file stream
        var stream = await _storage.DownloadAsync(id);
        if (stream == null)
        {
            return NotFound();
        }

        // Log access
        _logger.LogInformation(
            "File downloaded: {FileId} ({FileName}) by user {User}",
            id, metadata.FileName, User.Identity?.Name);

        // Return file with proper headers
        return File(stream, metadata.ContentType, metadata.FileName);
    }

    private Task<bool> AuthorizeDownloadAsync(FileMetadata metadata)
    {
        // Implement your authorization logic
        // Example: Check if user owns the file, has specific role, etc.
        return Task.FromResult(User.Identity?.IsAuthenticated == true);
    }
}

// View with secure download link
// <a asp-page="/Files/Download" asp-route-id="@Model.FileId" class="btn btn-primary">
//     Download
// </a>
```

### Pattern 5: Image Processing and Optimization

Handle image uploads with resizing and format optimization.

```csharp
public class ImageProcessingService
{
    private readonly IFileStorageService _storage;
    private readonly ILogger<ImageProcessingService> _logger;

    public ImageProcessingService(IFileStorageService storage, ILogger<ImageProcessingService> logger)
    {
        _storage = storage;
        _logger = logger;
    }

    public async Task<ImageUploadResult> ProcessAndUploadAsync(
        IFormFile file, 
        ImageProcessingOptions options,
        CancellationToken ct = default)
    {
        using var image = await Image.LoadAsync(file.OpenReadStream(), ct);
        
        // Resize if needed
        if (options.MaxWidth > 0 && image.Width > options.MaxWidth)
        {
            image.Mutate(x => x.Resize(options.MaxWidth, 0));
        }

        if (options.MaxHeight > 0 && image.Height > options.MaxHeight)
        {
            image.Mutate(x => x.Resize(0, options.MaxHeight));
        }

        // Optimize quality
        var encoder = GetEncoder(options.Format, options.Quality);
        
        using var outputStream = new MemoryStream();
        await image.SaveAsync(outputStream, encoder, ct);
        outputStream.Position = 0;

        var fileId = await _storage.UploadStreamAsync(
            outputStream, 
            file.FileName, 
            GetContentType(options.Format),
            ct);

        return new ImageUploadResult(
            fileId,
            image.Width,
            image.Height,
            outputStream.Length);
    }

    private IImageEncoder GetEncoder(ImageFormat format, int quality)
    {
        return format switch
        {
            ImageFormat.Jpeg => new JpegEncoder { Quality = quality },
            ImageFormat.Png => new PngEncoder(),
            ImageFormat.Webp => new WebpEncoder { Quality = quality },
            _ => new JpegEncoder { Quality = quality }
        };
    }

    private static string GetContentType(ImageFormat format) => format switch
    {
        ImageFormat.Jpeg => "image/jpeg",
        ImageFormat.Png => "image/png",
        ImageFormat.Webp => "image/webp",
        _ => "image/jpeg"
    };
}

public record ImageUploadResult(
    string FileId,
    int Width,
    int Height,
    long FileSize);

public class ImageProcessingOptions
{
    public int MaxWidth { get; set; }
    public int MaxHeight { get; set; }
    public int Quality { get; set; } = 85;
    public ImageFormat Format { get; set; } = ImageFormat.Jpeg;
}

public enum ImageFormat
{
    Jpeg,
    Png,
    Webp
}
```

## Anti-Patterns

```csharp
// ❌ BAD: Trusting file extension for validation
var extension = Path.GetExtension(file.FileName);
if (extension == ".jpg") // Only checks extension!
{
    // Malicious file could have .jpg extension but be executable
}

// ✅ GOOD: Validate file signature (magic numbers)
if (!await ValidateFileSignatureAsync(file))
{
    return ValidationResult.Failure("Invalid file content");
}

// ❌ BAD: Loading entire file into memory
using var memoryStream = new MemoryStream();
await file.CopyToAsync(memoryStream);
var bytes = memoryStream.ToArray(); // Memory explosion for large files!

// ✅ GOOD: Stream directly to storage
await _storage.UploadStreamAsync(file.OpenReadStream(), fileName, contentType);

// ❌ BAD: Using original file name for storage
var fileName = file.FileName; // Could be "../../../etc/passwd"
var path = Path.Combine(uploadsFolder, fileName);
await file.CopyToAsync(new FileStream(path, FileMode.Create));

// ✅ GOOD: Generate safe file name
var safeFileName = Path.GetFileName(file.FileName); // Removes path
var fileId = Guid.NewGuid().ToString("N");
var storagePath = Path.Combine(uploadsFolder, $"{fileId}{Path.GetExtension(safeFileName)}");

// ❌ BAD: No size limits
public async Task<IActionResult> OnPostAsync(IFormFile file)
{
    // Accepts files of any size - can crash the server!
}

// ✅ GOOD: Enforce size limits
[RequestSizeLimit(100 * 1024 * 1024)] // 100MB
[RequestFormLimits(MultipartBodyLengthLimit = 100 * 1024 * 1024)]
public async Task<IActionResult> OnPostAsync(IFormFile file)
{
    if (file.Length > 10 * 1024 * 1024) // 10MB per file
    {
        return BadRequest("File too large");
    }
}

// ❌ BAD: Synchronous file operations
public IActionResult OnPost(IFormFile file)
{
    file.CopyTo(stream); // Blocking call!
}

// ✅ GOOD: Async operations
public async Task<IActionResult> OnPostAsync(IFormFile file)
{
    await file.CopyToAsync(stream);
}

// ❌ BAD: No cleanup on failure
public async Task<string> UploadAsync(IFormFile file)
{
    var tempPath = Path.GetTempFileName();
    await file.CopyToAsync(System.IO.File.Create(tempPath));
    
    // If upload fails, temp file is never cleaned up!
    var result = await UploadToCloudAsync(tempPath);
    return result;
}

// ✅ GOOD: Proper cleanup
public async Task<string> UploadAsync(IFormFile file)
{
    var tempPath = Path.GetTempFileName();
    try
    {
        await using var stream = System.IO.File.Create(tempPath);
        await file.CopyToAsync(stream);
        return await UploadToCloudAsync(tempPath);
    }
    finally
    {
        if (System.IO.File.Exists(tempPath))
        {
            System.IO.File.Delete(tempPath);
        }
    }
}

// ❌ BAD: Exposing internal file paths
return Ok(new { FilePath = "/var/www/uploads/abc123.pdf" });

// ✅ GOOD: Use opaque identifiers
return Ok(new { FileId = "abc123", DownloadUrl = "/files/download/abc123" });

// ❌ BAD: No virus scanning
public async Task<IActionResult> OnPostAsync(IFormFile file)
{
    await _storage.UploadAsync(file); // Could upload malware!
}

// ✅ GOOD: Scan files before storage
public async Task<IActionResult> OnPostAsync(IFormFile file)
{
    var scanResult = await _virusScanner.ScanAsync(file);
    if (!scanResult.IsClean)
    {
        _logger.LogWarning("Malicious file upload attempted: {Threats}", scanResult.Threats);
        return BadRequest("File failed security scan");
    }
    
    await _storage.UploadAsync(file);
}
```

## References

- [File Uploads in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/mvc/models/file-uploads)
- [Multipart Section Reader](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.webutilities.multipartreader)
- [ImageSharp](https://sixlabors.com/products/imagesharp/) - Image processing library
- [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-dotnet)
- [OWASP File Upload Security](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html)
