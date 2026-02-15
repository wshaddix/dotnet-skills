# fly.toml Configuration Reference

## Table of Contents

- [Top-Level Settings](#top-level-settings)
- [Build Section](#build-section)
- [Deploy Section](#deploy-section)
- [Environment Variables](#environment-variables)
- [HTTP Service Section](#http-service-section)
- [Services Section](#services-section)
- [VM Section](#vm-section)
- [Mounts Section](#mounts-section)
- [Checks Section](#checks-section)
- [Metrics Section](#metrics-section)
- [Processes Section](#processes-section)
- [Statics Section](#statics-section)
- [Files Section](#files-section)
- [Restart Section](#restart-section)

## Top-Level Settings

```toml
app = "my-app"                  # App name, used as default hostname
primary_region = "ord"          # Region for new Machines; sets PRIMARY_REGION env var
kill_signal = "SIGINT"          # Signal on shutdown (default). Options: SIGTERM, SIGQUIT, SIGUSR1, SIGUSR2, SIGKILL, SIGSTOP
kill_timeout = 5                # Seconds after kill_signal before forced shutdown (max 300)
swap_size_mb = 512              # Enable Linux swap (MB)
console_command = "/bin/rails console"  # Command for `fly console`
```

Shutdown sequence: kill_signal -> wait kill_timeout -> SIGTERM unconditionally.

## Build Section

```toml
[build]
  image = "flyio/hellofly:latest"       # Use pre-built image (no build)
  dockerfile = "Dockerfile"              # Path to Dockerfile (default: ./Dockerfile)
  ignorefile = ".dockerignore"           # Path to .dockerignore
  build-target = "production"            # Multi-stage build target
  builder = "paketobuildpacks/builder:base"  # CNB builder image
  buildpacks = ["gcr.io/paketo-buildpacks/nodejs"]

  [build.args]
    NODE_ENV = "production"
    USER = "appuser"
```

Only one build method: `image`, `dockerfile`, or `builder`/`buildpacks`.

## Deploy Section

```toml
[deploy]
  release_command = "bin/rails db:migrate"   # Run before deploy (temporary Machine, no volumes)
  release_command_timeout = "10m"            # Override timeout (default 5m)
  strategy = "rolling"                       # rolling (default), immediate, canary, bluegreen
  max_unavailable = 0.33                     # Rolling: fraction (0-1) or integer
  wait_timeout = "5m"                        # Max wait for Machine start during deploy

  [deploy.release_command_vm]
    size = "performance-1x"
    memory = "2gb"
```

**Strategies**:
- **rolling**: One-by-one Machine replacement (default)
- **immediate**: Replace all at once, skip health check waits
- **canary**: Boot one new Machine, verify health, then rolling. Cannot be used with volumes
- **bluegreen**: Boot new Machines alongside old, migrate traffic after health checks. Requires health checks. Cannot be used with volumes

## Environment Variables

```toml
[env]
  LOG_LEVEL = "info"
  RAILS_ENV = "production"
  PORT = "8080"
```

Case-sensitive. Cannot start with `FLY_`. Secrets override env vars with same name.

## HTTP Service Section

Simplified service config for HTTP/HTTPS apps (ports 80/443 only):

```toml
[http_service]
  internal_port = 8080               # Port app listens on
  force_https = true                 # Redirect HTTP to HTTPS
  auto_stop_machines = "stop"        # "off", "stop", "suspend"
  auto_start_machines = true         # Start on incoming request
  min_machines_running = 1           # Min running in primary region
  processes = ["web"]                # Process groups

  [http_service.concurrency]
    type = "requests"                # "connections" or "requests"
    soft_limit = 200                 # Deprioritize above this (used for autoscale calc)
    hard_limit = 250                 # Stop routing at this limit

  [http_service.http_options]
    h2_backend = true                # HTTP/2 cleartext to app (for gRPC)
    idle_timeout = 60                # Connection idle timeout (seconds)

    [http_service.http_options.response]
      pristine = false               # true = don't add Server, Via, Fly-Request-Id headers

      [http_service.http_options.response.headers]
        Strict-Transport-Security = "max-age=31536000"
        X-Content-Type-Options = "nosniff"

  [http_service.tls_options]
    alpn = ["h2", "http/1.1"]
    versions = ["TLSv1.2", "TLSv1.3"]
    default_self_signed = false

  [[http_service.checks]]
    grace_period = "10s"
    interval = "30s"
    timeout = "5s"
    method = "GET"
    path = "/health"
    protocol = "http"                # "http" or "https"

    [http_service.checks.headers]
      Authorization = "Bearer healthcheck-token"

  [[http_service.machine_checks]]
    image = "curlimages/curl"
    command = ["curl", "-f", "http://$FLY_TEST_MACHINE_IP:8080/health"]
    kill_timeout = "30s"
```

## Services Section

Full-featured service definition (supports TCP, UDP, custom ports):

```toml
[[services]]
  internal_port = 8080
  protocol = "tcp"                   # "tcp" or "udp"
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0
  processes = ["web"]

  [services.concurrency]
    type = "connections"
    soft_limit = 25
    hard_limit = 30

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

    [services.ports.tls_options]
      alpn = ["h2", "http/1.1"]
      versions = ["TLSv1.2", "TLSv1.3"]

    [services.ports.http_options]
      h2_backend = false
      idle_timeout = 60

  [[services.tcp_checks]]
    grace_period = "5s"
    interval = "15s"
    timeout = "2s"

  [[services.http_checks]]
    grace_period = "10s"
    interval = "30s"
    timeout = "5s"
    method = "GET"
    path = "/health"
```

**Connection handlers** (in `services.ports.handlers`):
- `"http"` -- Normalize to HTTP/1.1, adds Fly headers
- `"tls"` -- TLS termination, forward plaintext
- `"pg_tls"` -- PostgreSQL-aware TLS
- `"proxy_proto"` -- PROXY protocol (v1 default, v2 with `proxy_proto_options = { version = "v2" }`)

No handlers = TCP pass-through.

## VM Section

```toml
[[vm]]
  size = "shared-cpu-1x"             # Preset (lower precedence than explicit keys)
  cpu_kind = "shared"                # "shared" or "performance"
  cpus = 1                           # 1, 2, 4, 8, 16
  memory = "512mb"                   # String with units or integer in MB
  gpu_kind = "l40s"                  # "a10", "l40s", "a100-pcie-40gb", "a100-sxm4-80gb"
  gpus = 1                           # Number of GPUs
  kernel_args = ""                   # Additional kernel boot params
  processes = ["web"]                # Target process groups

# Different sizing per process group
[[vm]]
  processes = ["worker"]
  memory = "256mb"
  cpu_kind = "shared"
  cpus = 1
```

## Mounts Section

```toml
[mounts]
  source = "mydata"                       # Volume name
  destination = "/data"                   # Mount path (cannot be "/")
  initial_size = "10gb"                   # Size on first deploy
  snapshot_retention = 5                  # Days to retain snapshots (1-60, default 5)
  scheduled_snapshots = true              # Automatic daily snapshots
  auto_extend_size_threshold = 80         # Usage % to trigger extend
  auto_extend_size_increment = "1GB"      # Amount to extend
  auto_extend_size_limit = "50GB"         # Max size after extensions
  processes = ["web"]                     # Limit to process groups

# Multiple mounts for different process groups
[[mounts]]
  source = "worker_data"
  destination = "/worker-data"
  processes = ["worker"]
```

## Checks Section

Top-level health checks (monitoring only, no routing impact):

```toml
[checks]
  [checks.app_health]
    type = "http"                    # "http" or "tcp"
    port = 8080
    path = "/health"
    method = "GET"
    interval = "30s"
    timeout = "5s"
    grace_period = "10s"
    processes = ["web"]

    [checks.app_health.headers]
      Content-Type = "application/json"

  [checks.worker_health]
    type = "tcp"
    port = 9090
    interval = "15s"
    timeout = "2s"
    processes = ["worker"]
```

## Metrics Section

```toml
[metrics]
  port = 9091
  path = "/metrics"

# Multiple metrics endpoints for different processes
[[metrics]]
  port = 9091
  path = "/metrics"
  processes = ["web"]

[[metrics]]
  port = 9092
  path = "/metrics"
  processes = ["worker"]
```

## Processes Section

```toml
[processes]
  web = "bin/rails server -b [::] -p 8080"
  worker = "bin/sidekiq"
  scheduler = "bin/clockwork config/clock.rb"
```

Process groups are referenced by `http_service`, `services`, `mounts`, `vm`, `checks`, `metrics`, `files`, and `restart` sections via the `processes` field.

## Statics Section

```toml
# Serve from Machine filesystem
[[statics]]
  guest_path = "/app/public"
  url_prefix = "/static"

# Serve from Tigris Object Storage
[[statics]]
  guest_path = "/assets"
  url_prefix = "/assets"
  tigris_bucket = "my-assets-bucket"
  index_document = "index.html"
```

Up to 10 mappings. `url_prefix` values must not overlap. Machine must be running.

## Files Section

Write files to Machines at deploy time:

```toml
# From base64-encoded value
[[files]]
  guest_path = "/etc/config.json"
  raw_value = "eyJrZXkiOiAidmFsdWUifQ=="

# From local file
[[files]]
  guest_path = "/etc/app.conf"
  local_path = "config/app.conf"

# From secret (must be base64-encoded)
[[files]]
  guest_path = "/etc/ssl/key.pem"
  secret_name = "TLS_KEY"
  processes = ["web"]
```

Exactly one source per entry: `raw_value`, `local_path`, or `secret_name`.

## Restart Section

```toml
[[restart]]
  policy = "on-failure"              # "always", "never", "on-failure" (default)
  retries = 5                        # Max restart attempts
  processes = ["web"]

[[restart]]
  policy = "always"
  processes = ["worker"]
```

## Fly Proxy Headers (HTTP Handler)

When using the HTTP handler, these headers are added to requests:

| Header | Description |
|---|---|
| `Fly-Client-IP` | Client IP connecting to Fly.io |
| `X-Forwarded-For` | Proxy chain IPs |
| `X-Forwarded-Proto` | `http` or `https` |
| `X-Forwarded-SSL` | `on` or `off` |
| `X-Forwarded-Port` | Original port (may be client-set) |
| `Fly-Forwarded-Port` | Original port (always Fly.io-set) |
| `Fly-Region` | Incoming connection region |

Routing preference headers (set by client):

| Header | Purpose |
|---|---|
| `Fly-Prefer-Region: iad` | Prefer specific region |
| `Fly-Prefer-Region: iad,ord,us` | Multi-region preference (ordered) |
| `Fly-Prefer-Instance-Id: <id>` | Prefer specific Machine |
| `Fly-Force-Instance-Id: <id>` | Force route to specific Machine |
