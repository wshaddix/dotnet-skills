---
name: slopwatch
description: Patterns for detecting and managing code smells and technical debt in .NET applications. Run Slopwatch CLI to detect LLM reward hacking, disabled tests, suppressed warnings, empty catches, and other shortcuts. Use when identifying code smells, running quality gates in CI/CD, or validating LLM-generated code changes.
---

# Slopwatch: LLM Anti-Cheat for .NET

## When to Use This Skill

**Use this skill constantly.** Every time an LLM (including Claude) makes changes to:
- C# source files (.cs)
- Project files (.csproj)
- Props files (Directory.Build.props, Directory.Packages.props)
- Test files

Run slopwatch to validate the changes don't introduce "slop."

---

## What is Slop?

"Slop" refers to shortcuts LLMs take that make tests pass or builds succeed without actually solving the underlying problem. These are reward hacking behaviors - the LLM optimizes for apparent success rather than real fixes.

### Common Slop Patterns

| Pattern | Example | Why It's Bad |
|---------|---------|--------------|
| Disabled tests | `[Fact(Skip="flaky")]` | Hides failures instead of fixing them |
| Warning suppression | `#pragma warning disable CS8618` | Silences compiler without fixing issue |
| Empty catch blocks | `catch (Exception) { }` | Swallows errors, hides bugs |
| Arbitrary delays | `await Task.Delay(1000);` | Masks race conditions, makes tests slow |
| Project-level suppression | `<NoWarn>CS1591</NoWarn>` | Disables warnings project-wide |
| CPM bypass | `Version="1.0.0"` inline | Undermines central package management |

**Never accept these patterns.** If an LLM introduces slop, reject the change and require a proper fix.

---

## Installation

### As a Local Tool (Recommended)

Add to `.config/dotnet-tools.json`:

```json
{
  "version": 1,
  "isRoot": true,
  "tools": {
    "slopwatch.cmd": {
      "version": "0.3.3",
      "commands": ["slopwatch"],
      "rollForward": false
    }
  }
}
```

Then restore:
```bash
dotnet tool restore
```

### As a Global Tool

```bash
dotnet tool install --global Slopwatch.Cmd
```

---

## First-Time Setup: Establish a Baseline

Before using slopwatch on an existing project, create a baseline:

```bash
# Initialize baseline from existing code
slopwatch init

# This creates .slopwatch/baseline.json
git add .slopwatch/baseline.json
git commit -m "Add slopwatch baseline"
```

**Why baseline?** Legacy code may have existing issues. The baseline ensures slopwatch only catches **new** slop being introduced.

---

## Usage

### Basic Analysis

```bash
# Analyze current directory for slop
slopwatch analyze

# Analyze specific directory
slopwatch analyze -d ./src

# Strict mode -- fail on warnings too
slopwatch analyze --fail-on warning

# JSON output for tooling integration
slopwatch analyze --output json

# Show performance stats
slopwatch analyze --stats
```

### Updating the Baseline (Rare)

Only update when slop is **truly justified** and documented:

```bash
slopwatch analyze --update-baseline
```

Valid reasons: third-party library forces a pattern, intentional rate-limiting delay (not test flakiness), generated code that cannot be modified. Always add a code comment explaining the justification.

---

## Configuration

Create `.slopwatch/slopwatch.json` to customize:

```json
{
  "minSeverity": "warning",
  "rules": {
    "SW001": { "enabled": true, "severity": "error" },
    "SW002": { "enabled": true, "severity": "warning" },
    "SW003": { "enabled": true, "severity": "error" },
    "SW004": { "enabled": true, "severity": "warning" },
    "SW005": { "enabled": true, "severity": "warning" },
    "SW006": { "enabled": true, "severity": "warning" }
  },
  "exclude": [
    "**/Generated/**",
    "**/obj/**",
    "**/bin/**"
  ]
}
```

### Strict Mode (Recommended for LLM Sessions)

```json
{
  "minSeverity": "warning",
  "rules": {
    "SW001": { "enabled": true, "severity": "error" },
    "SW002": { "enabled": true, "severity": "error" },
    "SW003": { "enabled": true, "severity": "error" },
    "SW004": { "enabled": true, "severity": "error" },
    "SW005": { "enabled": true, "severity": "error" },
    "SW006": { "enabled": true, "severity": "error" }
  }
}
```

---

## Detection Rules

| Rule | Severity | What It Catches |
|------|----------|-----------------|
| SW001 | Error | Disabled tests (`Skip=`, `Ignore`, `#if false`) |
| SW002 | Warning | Warning suppression (`#pragma warning disable`, `SuppressMessage`) |
| SW003 | Error | Empty catch blocks that swallow exceptions |
| SW004 | Warning | Arbitrary delays in tests (`Task.Delay`, `Thread.Sleep`) |
| SW005 | Warning | Project file slop (`NoWarn`, `TreatWarningsAsErrors=false`) |
| SW006 | Warning | CPM bypass (`VersionOverride`, inline `Version` attributes) |

### When Slopwatch Flags an Issue

```
❌ SW001 [Error]: Disabled test detected
   File: tests/MyApp.Tests/OrderTests.cs:45
   Pattern: [Fact(Skip="Test is flaky")]
```

1. **Understand why** the LLM took the shortcut
2. **Request a proper fix** - be specific about what's wrong
3. **Verify the fix** doesn't introduce different slop

**Never disable tests to achieve a green build.** Fix the underlying issue.

---

## Claude Code Hook Integration

Add slopwatch as a hook to automatically validate every edit. Create or update `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "slopwatch analyze -d . --hook",
            "timeout": 60000
          }
        ]
      }
    ]
  }
}
```

The `--hook` flag:
- Only analyzes **git dirty files** (fast, even on large repos)
- Outputs errors to stderr in readable format
- Blocks the edit on warnings/errors (exit code 2)
- Claude sees the error and can fix it immediately

---

## CI/CD Integration

### GitHub Actions

```yaml
jobs:
  slopwatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Install Slopwatch
        run: dotnet tool install --global Slopwatch.Cmd

      - name: Run Slopwatch
        run: slopwatch analyze -d . --fail-on warning
```

### Azure Pipelines

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Install Slopwatch'
  inputs:
    command: 'custom'
    custom: 'tool'
    arguments: 'install --global Slopwatch.Cmd'

- script: slopwatch analyze -d . --fail-on warning
  displayName: 'Slopwatch Analysis'
```

---

## The Philosophy: Zero Tolerance for New Slop

1. **Baseline captures legacy** - Existing issues are acknowledged but isolated
2. **New slop is blocked** - Any new shortcut fails the build/edit
3. **Exceptions require justification** - If you must update baseline, document why
4. **LLMs are not special** - The same rules apply to human and AI-generated code

---

## Quick Reference

```bash
# First time setup
slopwatch init
git add .slopwatch/baseline.json

# After every LLM code change
slopwatch analyze

# Strict mode (recommended)
slopwatch analyze --fail-on warning

# With stats (performance debugging)
slopwatch analyze --stats

# Update baseline (rare, document why)
slopwatch analyze --update-baseline

# JSON output for tooling
slopwatch analyze --output json

# Hook mode (for Claude Code integration)
slopwatch analyze -d . --hook
```

---

## When to Override (Almost Never)

The only valid reasons to update baseline or disable a rule:

| Scenario | Action | Required |
|----------|--------|----------|
| Third-party forces pattern | Update baseline | Code comment explaining why |
| Generated code (not editable) | Add to exclude list | Document in config |
| Intentional rate limiting delay | Update baseline | Code comment, not in test |
| Legacy code cleanup | One-time baseline update | PR description |

**Invalid reasons:**
- "The test is flaky" → Fix the flakiness
- "The warning is annoying" → Fix the code
- "It works on my machine" → Fix the race condition
- "We'll fix it later" → Fix it now

---

## Agent Gotchas

- **Do not suppress slopwatch findings.** If slopwatch flags an issue, fix the code.
- **Run after every code change**, not just at the end.
- **Use `--hook` flag in Claude Code hooks**, not bare `analyze`.
- **Baseline is not a wastebasket.** Adding items requires documented justification.
- **Local tool preferred over global.** Use `.config/dotnet-tools.json`.

---

## References

- [Slopwatch NuGet Package](https://www.nuget.org/packages/Slopwatch.Cmd)
