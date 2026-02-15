# Fly.io Databases & Storage Reference

## Table of Contents

- [Managed Postgres](#managed-postgres)
- [Tigris Object Storage](#tigris-object-storage)
- [Upstash Redis](#upstash-redis)
- [Volumes as Storage](#volumes-as-storage)
- [Connection Patterns](#connection-patterns)

## Managed Postgres

Fly.io's fully managed PostgreSQL service. Handles provisioning, backups, failover.

```bash
fly mpg create                           # Create a new cluster (interactive)
fly mpg list                             # List clusters
fly mpg status <cluster-name>            # Cluster details
fly mpg connect <cluster-name>           # Connect via psql
fly mpg config show <cluster-name>       # Show configuration
fly mpg config update <cluster-name>     # Update configuration
```

**Connection**: Set the `DATABASE_URL` secret to the connection string provided during creation.

```bash
fly secrets set DATABASE_URL="postgres://user:pass@my-db.flycast:5432/mydb"
```

**Best practices**:
- Use Flycast address for internal connectivity
- Practice disaster recovery by testing backup restoration from the dashboard
- Choose cluster configuration based on workload (CPU, memory, storage)

**Extensions**: Managed Postgres supports many PostgreSQL extensions. Check `fly mpg extensions list` for available extensions.

## Tigris Object Storage

S3-compatible global object storage, powered by Tigris.

```bash
fly storage create                       # Create a Tigris bucket (interactive)
fly storage list                         # List buckets
fly storage dashboard <bucket-name>      # Open Tigris dashboard
```

**Access**: Use standard S3 SDKs with Tigris credentials. Credentials are automatically set as secrets:
- `BUCKET_NAME`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ENDPOINT_URL_S3`
- `AWS_REGION`

**Serve static files from Tigris**:

```toml
[[statics]]
  guest_path = "/assets"
  url_prefix = "/assets"
  tigris_bucket = "my-assets-bucket"
  index_document = "index.html"
```

## Upstash Redis

Managed Redis via Fly.io's Upstash integration.

```bash
fly redis create                         # Create Redis instance
fly redis list                           # List instances
fly redis status <name>                  # Instance details
fly redis dashboard <name>              # Open dashboard
```

Connection string set automatically as `REDIS_URL` secret. Accessible over private networking.

## Volumes as Storage

Fly Volumes provide NVMe-backed persistent storage mounted into Machines.

```bash
fly volumes create mydata --region ord --size 10   # Create 10GB volume
fly volumes list                                    # List volumes
fly volumes show <vol-id>                           # Volume details
fly volumes extend <vol-id> --size 20               # Extend (cannot shrink)
fly volumes fork <vol-id>                           # Copy a volume
fly volumes snapshots list <vol-id>                 # List snapshots
fly volumes snapshots create <vol-id>               # Create on-demand snapshot
```

**Key constraints**:
- 1:1 mapping: one volume per Machine, one Machine per volume
- Region-pinned: volume exists on one server in one region
- No automatic replication between volumes
- Max size: 500GB
- Encrypted at rest by default

**Auto-extend in fly.toml**:

```toml
[mounts]
  source = "mydata"
  destination = "/data"
  auto_extend_size_threshold = 80       # Extend at 80% usage
  auto_extend_size_increment = "1GB"
  auto_extend_size_limit = "50GB"
```

**Volume snapshots**: Daily automatic snapshots retained for 5 days (configurable 1-60 days). Not a replacement for proper backups. Restore creates a new volume of equal or greater size.

**Not available during**:
- Docker image builds (`fly deploy` build phase)
- Release commands (temporary Machine)

## Connection Patterns

### App to Managed Postgres

```bash
# Set connection string as secret
fly secrets set DATABASE_URL="postgres://user:pass@my-db.flycast:5432/mydb"
```

Use Flycast address for private access with Fly Proxy features. Use `.internal` address for direct 6PN connection.

### App to Redis

```bash
# Usually auto-configured, but can set manually
fly secrets set REDIS_URL="redis://default:pass@my-redis.flycast:6379"
```

### App to Tigris

Use S3 SDK with environment variables auto-set by Fly.io:

```python
import boto3

s3 = boto3.client('s3')  # Auto-reads AWS_* env vars
s3.put_object(Bucket=os.environ['BUCKET_NAME'], Key='file.txt', Body=data)
```

### Multi-App Architecture

All apps in an organization share private networking. Typical patterns:

```
[web app] --flycast--> [api app] --6pn--> [database app]
                           |
                           +--6pn--> [worker app]
```

- Use Flycast addresses for services that benefit from autostop/autostart
- Use `.internal` DNS for direct connections (lower latency, no proxy)
- Store connection info in secrets, not hardcoded
