---
name: fly-io
description: Deploy, configure, and manage applications on the Fly.io platform using flyctl CLI, fly.toml configuration, Fly Machines, Fly Volumes, private networking, secrets, health checks, autoscaling, and GitHub Actions CI/CD. Use when deploying any application to Fly.io, writing or modifying fly.toml configuration, managing Fly Machines or Volumes, configuring networking (public services, private 6PN, Flycast, custom domains, TLS), setting secrets, configuring health checks, setting up autostop/autostart or metrics-based autoscaling, deploying with GitHub Actions, managing Fly Postgres databases, or preparing an app for production on Fly.io.
---

# Fly.io Deployment & Management

## Core Concepts

- **Fly App**: Named group of Machines (VMs) + config + networking + secrets belonging to one org
- **Fly Machine**: Fast-launching VM (sub-second start). Ephemeral root filesystem. Lifecycle: created -> started -> stopped -> destroyed
- **Fly Volume**: NVMe-backed persistent storage, 1:1 with a Machine, region-pinned, encrypted at rest by default
- **Fly Proxy**: Edge proxy handling TLS termination, load balancing, autostop/autostart, HTTP routing
- **flyctl (fly)**: CLI for all Fly.io operations. Install: `brew install flyctl` or `curl -L https://fly.io/install.sh | sh`
- **fly.toml**: App configuration file. See [references/fly-toml-config.md](references/fly-toml-config.md) for complete reference

## Quick Start Workflow

```bash
# 1. Create app + fly.toml
fly launch

# 2. Set secrets
fly secrets set DATABASE_URL=postgres://... SECRET_KEY=...

# 3. Deploy
fly deploy

# 4. Check status
fly status
fly logs
```

## fly.toml Essentials

Minimal web app configuration:

```toml
app = 'my-app'
primary_region = 'ord'

[build]
  dockerfile = "Dockerfile"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "requests"
    soft_limit = 200
    hard_limit = 250

[[vm]]
  memory = '512mb'
  cpu_kind = 'shared'
  cpus = 1
```

For the complete fly.toml reference with all sections, see [references/fly-toml-config.md](references/fly-toml-config.md).

## Machines Management

```bash
# Scale horizontally
fly scale count 3                          # 3 Machines in primary region
fly scale count 3 --region ord,iad         # Across regions

# Scale vertically
fly scale vm performance-1x --vm-memory 2048

# Direct Machine control
fly machine run <image> --region ord
fly machine clone <machine-id> --region iad
fly machine update <machine-id> --vm-memory 512
fly machine stop <machine-id>
fly machine start <machine-id>
fly machine destroy <machine-id>
```

Machine sizes: `shared-cpu-1x` (256MB default), `shared-cpu-2x`, `shared-cpu-4x`, `shared-cpu-8x`, `performance-1x` through `performance-16x`. GPU options: `a10`, `l40s`, `a100-pcie-40gb`, `a100-sxm4-80gb`.

## Volumes

```bash
fly volumes create mydata --region ord --size 10   # 10GB
fly volumes list
fly volumes extend <vol-id> --size 20              # Extend to 20GB (cannot shrink)
fly volumes snapshots list <vol-id>
fly volumes fork <vol-id>                          # Copy a volume
```

Configure in fly.toml:

```toml
[mounts]
  source = "mydata"
  destination = "/data"
  initial_size = "10gb"
  auto_extend_size_threshold = 80
  auto_extend_size_increment = "1GB"
  auto_extend_size_limit = "50GB"
```

**Critical**: Volumes are 1:1 with Machines, region-pinned, no automatic replication. Always provision at least 2 Machines with volumes for redundancy. Your app must handle data replication between volumes.

## Secrets

```bash
fly secrets set KEY=value OTHER_KEY=other_value
fly secrets set KEY=value --stage               # Stage without restarting
fly secrets deploy                               # Deploy staged secrets
fly secrets list                                 # Names only, no values
fly secrets unset KEY OTHER_KEY
```

Secrets are encrypted at rest, injected as env vars at boot. Use `[[files]]` in fly.toml to mount secrets as files (value must be base64-encoded):

```toml
[[files]]
  guest_path = "/etc/ssl/private/key.pem"
  secret_name = "TLS_PRIVATE_KEY"
```

## Networking

For detailed networking patterns (public services, private networking, Flycast, custom domains, DNS), see [references/networking.md](references/networking.md).

### Quick Reference

```bash
fly ips list                                 # List allocated IPs
fly ips allocate-v6                          # Dedicated IPv6 (free)
fly ips allocate-v4 --shared                 # Shared IPv4 (free)
fly ips allocate-v4                          # Dedicated IPv4 (paid)
fly certs create mydomain.com                # Add custom domain + TLS cert
```

**Private networking**: All apps in an org share a WireGuard mesh (6PN). Use `<appname>.internal` DNS for inter-app communication. Bind to `fly-local-6pn` or `[::]:port` to accept private connections.

## Health Checks

Service-level checks affect Fly Proxy routing. Top-level `[checks]` are for monitoring only.

```toml
# In [http_service] or [[services]]
[[http_service.checks]]
  grace_period = "10s"
  interval = "30s"
  timeout = "5s"
  method = "GET"
  path = "/health"

# Top-level (monitoring, no routing impact)
[checks.my_check]
  type = "http"
  port = 8080
  path = "/health"
  interval = "30s"
  timeout = "5s"
```

## Autoscaling

**Autostop/autostart** (Fly Proxy-based, for web services):

```toml
[http_service]
  auto_stop_machines = "stop"      # "off", "stop", or "suspend"
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "requests"
    soft_limit = 200               # Used for excess capacity calculation
```

**Metrics-based autoscaling**: Deploy the autoscaler app in your org. It polls Prometheus metrics and creates/destroys Machines. See Fly.io docs for setup.

## Deployment Strategies

```toml
[deploy]
  strategy = "rolling"              # "rolling" (default), "immediate", "canary", "bluegreen"
  max_unavailable = 0.33            # For rolling: fraction or integer
  release_command = "bin/migrate"   # One-off command before deploy (e.g., DB migrations)
```

- **rolling**: One-by-one replacement (default)
- **immediate**: All at once, skip health check waits
- **canary**: Boot one Machine, verify health, then rolling (no volumes)
- **bluegreen**: Boot new set alongside old, migrate traffic after health checks (requires health checks, no volumes)

## CI/CD with GitHub Actions

For complete CI/CD setup including deploy tokens, review apps, and multi-app deploys, see [references/cicd-github-actions.md](references/cicd-github-actions.md).

Quick setup:

```yaml
# .github/workflows/fly.yml
name: Fly Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    concurrency: deploy-group
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

Generate deploy token: `fly tokens create deploy -x 999999h`

## Databases & Storage

For detailed database and storage patterns, see [references/databases-storage.md](references/databases-storage.md).

- **Managed Postgres**: `fly mpg create` -- fully managed, automated backups
- **Tigris Object Storage**: S3-compatible, `fly storage create`
- **Upstash Redis**: Managed Redis, `fly redis create`

## Production Checklist

1. **Security**: Enable SSO, use secrets for sensitive data, release unnecessary public IPs from private apps, use Flycast for internal services
2. **Performance**: Use performance CPUs for production web apps, right-size memory, enable swap (`swap_size_mb`) for spike absorption
3. **Availability**: Run 2+ Machines (ideally across regions), configure autostop/autostart, set up health checks
4. **Networking**: Set up custom domain + TLS cert, consider dedicated IPv4 if needed
5. **Monitoring**: Configure Prometheus metrics export, set up Sentry, export logs to external service
6. **CI/CD**: Deploy via GitHub Actions with deploy tokens, set up review app previews

## Process Groups

Run multiple processes in one app (e.g., web + worker):

```toml
[processes]
  web = "bin/rails server -b 0.0.0.0 -p 8080"
  worker = "bin/sidekiq"

[http_service]
  internal_port = 8080
  processes = ["web"]

[[vm]]
  processes = ["web"]
  memory = "1gb"

[[vm]]
  processes = ["worker"]
  memory = "512mb"
```

## Useful Commands Cheat Sheet

| Command | Description |
|---|---|
| `fly launch` | Create app + fly.toml |
| `fly deploy` | Build and deploy |
| `fly deploy --remote-only` | Build on Fly.io builders |
| `fly status` | App and Machine status |
| `fly logs` | Tail live logs |
| `fly ssh console -s` | SSH into a Machine (select) |
| `fly proxy 5432:5432` | Proxy local port to app |
| `fly dashboard` | Open web dashboard |
| `fly scale show` | Show current scaling |
| `fly checks list` | View health check status |
| `fly releases` | List releases |
| `fly config show` | Show current fly.toml |
| `fly apps restart` | Restart all Machines |
