---
name: project-structure
description: Guidelines for organizing .NET projects, including solution structure, project references, folder conventions, .slnx format, centralized build properties, and central package management. Use when setting up a new .NET solution with modern best practices, configuring centralized build properties across multiple projects, implementing central package version management, or setting up SourceLink for debugging.
---

# .NET Project Structure and Build Configuration

## When to Use This Skill

Use this skill when:
- Setting up a new .NET solution with modern best practices
- Configuring centralized build properties across multiple projects
- Implementing central package version management
- Setting up SourceLink for debugging and NuGet packages
- Automating version management with release notes
- Pinning SDK versions for consistent builds

---

## Recommended Solution Layout

```
MyApp/
├── .config/
│   └── dotnet-tools.json           # Local .NET tools
├── .editorconfig
├── .gitignore
├── global.json
├── nuget.config
├── Directory.Build.props
├── Directory.Build.targets
├── Directory.Packages.props
├── MyApp.slnx                       # .NET 9+ SDK / VS 17.13+
├── src/
│   ├── MyApp.Core/
│   │   └── MyApp.Core.csproj
│   ├── MyApp.Api/
│   │   ├── MyApp.Api.csproj
│   │   ├── Program.cs
│   │   └── appsettings.json
│   └── MyApp.Infrastructure/
│       └── MyApp.Infrastructure.csproj
└── tests/
    ├── MyApp.UnitTests/
    │   └── MyApp.UnitTests.csproj
    └── MyApp.IntegrationTests/
        └── MyApp.IntegrationTests.csproj
```

Key principles:
- Separate `src/` and `tests/` directories
- One project per concern (Core/Domain, Infrastructure, API/Host)
- Solution file at the repo root
- All shared build configuration at the repo root

---

## Solution File Formats

### .slnx (Modern — .NET 9+)

The XML-based solution format is human-readable and diff-friendly. Requires .NET 9+ SDK or Visual Studio 17.13+.

```xml
<Solution>
  <Folder Name="/build/">
    <File Path="Directory.Build.props" />
    <File Path="Directory.Packages.props" />
    <File Path="global.json" />
    <File Path="NuGet.Config" />
  </Folder>
  <Folder Name="/src/">
    <Project Path="src/MyApp.Core/MyApp.Core.csproj" />
    <Project Path="src/MyApp.Api/MyApp.Api.csproj" />
    <Project Path="src/MyApp.Infrastructure/MyApp.Infrastructure.csproj" />
  </Folder>
  <Folder Name="/tests/">
    <Project Path="tests/MyApp.UnitTests/MyApp.UnitTests.csproj" />
    <Project Path="tests/MyApp.IntegrationTests/MyApp.IntegrationTests.csproj" />
  </Folder>
</Solution>
```

### Migrating from .sln to .slnx

```bash
dotnet sln MySolution.sln migrate
```

**Important:** Do not keep both `.sln` and `.slnx` files in the same repository.

### Creating a New .slnx Solution

```bash
# .NET 10+: Creates .slnx by default
dotnet new sln --name MySolution

# .NET 9: Specify the format explicitly
dotnet new sln --name MySolution --format slnx

dotnet sln add src/MyApp/MyApp.csproj
```

### Benefits

- Dramatically fewer merge conflicts
- Human-readable and editable
- Consistent with modern `.csproj` format
- Better diff/review experience in pull requests

---

## Directory.Build.props

Shared MSBuild properties applied to all projects in the directory subtree.

```xml
<Project>
  <!-- Metadata -->
  <PropertyGroup>
    <Authors>Your Team</Authors>
    <Company>Your Company</Company>
    <Copyright>Copyright © 2020-$([System.DateTime]::Now.Year) Your Company</Copyright>
    <Product>Your Product</Product>
    <PackageProjectUrl>https://github.com/yourorg/yourrepo</PackageProjectUrl>
    <RepositoryUrl>https://github.com/yourorg/yourrepo</RepositoryUrl>
    <PackageLicenseExpression>Apache-2.0</PackageLicenseExpression>
  </PropertyGroup>

  <!-- C# Language Settings -->
  <PropertyGroup>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <AnalysisLevel>latest-all</AnalysisLevel>
    <NoWarn>$(NoWarn);CS1591</NoWarn>
  </PropertyGroup>

  <!-- Target Framework Definitions -->
  <PropertyGroup>
    <NetStandardLibVersion>netstandard2.0</NetStandardLibVersion>
    <NetLibVersion>net8.0</NetLibVersion>
    <NetTestVersion>net9.0</NetTestVersion>
  </PropertyGroup>

  <!-- SourceLink Configuration -->
  <PropertyGroup>
    <PublishRepositoryUrl>true</PublishRepositoryUrl>
    <EmbedUntrackSources>true</EmbedUntrackSources>
    <IncludeSymbols>true</IncludeSymbols>
    <SymbolPackageFormat>snupkg</SymbolPackageFormat>
    <DebugType>embedded</DebugType>
    <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.SourceLink.GitHub" PrivateAssets="All" />
  </ItemGroup>

  <!-- NuGet Package Assets -->
  <ItemGroup>
    <None Include="$(MSBuildThisFileDirectory)logo.png" Pack="true" PackagePath="\" />
    <None Include="$(MSBuildThisFileDirectory)README.md" Pack="true" PackagePath="\" />
  </ItemGroup>

  <PropertyGroup>
    <PackageIcon>logo.png</PackageIcon>
    <PackageReadmeFile>README.md</PackageReadmeFile>
  </PropertyGroup>

  <!-- Global Using Statements -->
  <ItemGroup>
    <Using Include="System.Collections.Immutable" />
  </ItemGroup>
</Project>
```

### Nested Directory.Build.props

Inner files do **not** automatically import outer files:

```xml
<!-- src/Directory.Build.props -->
<Project>
  <Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />
  <PropertyGroup>
    <!-- src-specific settings -->
  </PropertyGroup>
</Project>
```

---

## Directory.Build.targets

Imported **after** project evaluation. Use for:
- Shared analyzer package references
- Custom build targets
- Conditional logic based on project type

```xml
<Project>
  <ItemGroup>
    <PackageReference Include="Meziantou.Analyzer" PrivateAssets="all" />
    <PackageReference Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

---

## Directory.Packages.props - Central Package Management

CPM centralizes all NuGet package versions at the repo root. Individual `.csproj` files reference packages **without** a `Version` attribute.

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>

  <PropertyGroup>
    <AkkaVersion>1.5.35</AkkaVersion>
    <AspireVersion>9.1.0</AspireVersion>
  </PropertyGroup>

  <ItemGroup Label="App Dependencies">
    <PackageVersion Include="Akka" Version="$(AkkaVersion)" />
    <PackageVersion Include="Akka.Cluster" Version="$(AkkaVersion)" />
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="9.0.0" />
  </ItemGroup>

  <ItemGroup Label="Test Dependencies">
    <PackageVersion Include="xunit.v3" Version="3.2.2" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="3.1.5" />
    <PackageVersion Include="FluentAssertions" Version="7.0.0" />
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
    <PackageVersion Include="coverlet.collector" Version="8.0.0" />
  </ItemGroup>

  <ItemGroup Label="Build Dependencies">
    <PackageVersion Include="Microsoft.SourceLink.GitHub" Version="8.0.0" />
  </ItemGroup>
</Project>
```

### Consuming Packages (No Version Needed)

```xml
<!-- In MyApp.csproj -->
<ItemGroup>
  <PackageReference Include="Akka" />
  <PackageReference Include="Microsoft.Extensions.Hosting" />
</ItemGroup>
```

### Version Overrides

```xml
<PackageReference Include="Newtonsoft.Json" VersionOverride="13.0.3" />
```

---

## .editorconfig

Place at the repo root to enforce consistent code style:

```ini
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{csproj,props,targets,xml,json,yml,yaml}]
indent_size = 2

[*.cs]
csharp_style_namespace_declarations = file_scoped:warning
csharp_prefer_braces = true:warning
csharp_style_var_for_built_in_types = true:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
dotnet_style_require_accessibility_modifiers = always:warning
csharp_style_prefer_pattern_matching = true:suggestion
csharp_style_prefer_switch_expression = true:suggestion
csharp_using_directive_placement = outside_namespace:warning
dotnet_sort_system_directives_first = true

dotnet_naming_rule.private_fields_should_be_camel_case.symbols = private_fields
dotnet_naming_rule.private_fields_should_be_camel_case.style = camel_case_underscore
dotnet_naming_rule.private_fields_should_be_camel_case.severity = warning
dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private
dotnet_naming_style.camel_case_underscore.required_prefix = _
dotnet_naming_style.camel_case_underscore.capitalization = camel_case
```

---

## global.json - SDK Version Pinning

```json
{
  "sdk": {
    "version": "9.0.200",
    "rollForward": "latestFeature"
  }
}
```

### Roll Forward Policies

| Policy | Behavior |
|--------|----------|
| `disable` | Exact version required |
| `patch` | Same major.minor, latest patch |
| `feature` | Same major, latest minor.patch |
| `latestFeature` | Same major, latest feature band |
| `minor` | Same major, latest minor |
| `latestMinor` | Same major, latest minor |
| `major` | Latest SDK (not recommended) |

**Recommended:** `latestFeature` - Allows patch updates within the same feature band.

---

## nuget.config

Configure package sources and security:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <solution>
    <add key="disableSourceControlIntegration" value="true" />
  </solution>

  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>

  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
```

The `<clear />` + explicit sources + `<packageSourceMapping>` pattern prevents supply-chain attacks.

For private feeds:

```xml
<packageSources>
  <clear />
  <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  <add key="internal" value="https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json" />
</packageSources>
<packageSourceMapping>
  <packageSource key="nuget.org">
    <package pattern="*" />
  </packageSource>
  <packageSource key="internal">
    <package pattern="MyCompany.*" />
  </packageSource>
</packageSourceMapping>
```

---

## NuGet Audit

.NET 9+ enables `NuGetAudit` by default:

```xml
<PropertyGroup>
  <NuGetAudit>true</NuGetAudit>
  <NuGetAuditLevel>low</NuGetAuditLevel>
  <NuGetAuditMode>all</NuGetAuditMode>
</PropertyGroup>
```

---

## Lock Files

Enable deterministic restores:

```xml
<PropertyGroup>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
</PropertyGroup>
```

In CI:

```bash
dotnet restore --locked-mode
```

---

## SourceLink and Deterministic Builds

For libraries published to NuGet:

```xml
<PropertyGroup>
  <PublishRepositoryUrl>true</PublishRepositoryUrl>
  <EmbedUntrackSources>true</EmbedUntrackSources>
  <DebugType>embedded</DebugType>
  <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="Microsoft.SourceLink.GitHub" PrivateAssets="all" />
</ItemGroup>
```

---

## Version Management with RELEASE_NOTES.md

```markdown
#### 1.2.0 January 15th 2025 ####

- Added new feature X
- Fixed bug in Y

#### 1.1.0 December 10th 2024 ####

- Initial release
```

### CI/CD Integration

```yaml
- name: Update version from release notes
  shell: pwsh
  run: ./build.ps1

- name: Build
  run: dotnet build -c Release

- name: Pack with tag version
  run: dotnet pack -c Release /p:PackageVersion=${{ github.ref_name }}
```

---

## Quick Reference

| File | Purpose |
|------|---------|
| `MySolution.slnx` | Modern XML solution file |
| `Directory.Build.props` | Centralized build properties |
| `Directory.Packages.props` | Central package version management |
| `global.json` | SDK version pinning |
| `NuGet.Config` | Package source configuration |
| `RELEASE_NOTES.md` | Version history |
| `.editorconfig` | Code style enforcement |
| `.config/dotnet-tools.json` | Local .NET tools |

---

## References

- [.NET Library Design Guidance](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management)
- [.slnx Format](https://learn.microsoft.com/en-us/visualstudio/ide/reference/solution-file)
- [Directory.Build.props](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-your-build)
- [SourceLink](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/sourcelink)
- [NuGet Audit](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages)
