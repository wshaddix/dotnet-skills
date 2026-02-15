# Fly.io Networking Reference

## Table of Contents

- [Public Networking](#public-networking)
- [IP Addresses](#ip-addresses)
- [Custom Domains & TLS](#custom-domains--tls)
- [Private Networking (6PN)](#private-networking-6pn)
- [Internal DNS](#internal-dns)
- [Flycast (Private Proxy)](#flycast-private-proxy)
- [Dynamic Request Routing](#dynamic-request-routing)
- [WireGuard VPN](#wireguard-vpn)
- [Egress IPs](#egress-ips)

## Public Networking

Fly Proxy routes public internet traffic to your app. Default-deny: nothing is exposed unless configured via `[http_service]` or `[[services]]` in fly.toml.

All traffic hits Anycast edge servers globally. Fly Proxy handles TLS termination, HTTP normalization, load balancing, and connection routing to the nearest healthy Machine.

## IP Addresses

```bash
fly ips list                           # List allocated IPs
fly ips allocate-v6                    # Dedicated IPv6 (free, auto on first deploy)
fly ips allocate-v4 --shared           # Shared IPv4 (free, auto for HTTP/HTTPS apps)
fly ips allocate-v4                    # Dedicated IPv4 (billed monthly)
fly ips release <ip-address>           # Release an IP
```

**Shared IPv4** (recommended for most apps):
- Free, shared across apps/orgs
- Routing based on app domain
- Auto-allocated for apps with HTTP on port 80 or TLS+HTTP on port 443
- Works for non-80/443 TCP ports when using TLS handler

**Dedicated IPv4** (use when):
- Non-HTTP protocol without TLS
- UDP required (no shared IPv4/IPv6 UDP support)
- Raw TCP with self-managed TLS termination
- Fly Postgres exposed to internet over TLS

## Custom Domains & TLS

```bash
fly certs create mydomain.com          # Add domain + auto-provision TLS cert
fly certs list                         # List certificates
fly certs show mydomain.com            # Show cert details
fly certs delete mydomain.com          # Remove certificate
```

**DNS setup**:
- CNAME: `mydomain.com` -> `my-app.fly.dev`
- Or A record: `mydomain.com` -> shared/dedicated IPv4
- Plus AAAA record: `mydomain.com` -> IPv6 address

Certificates are auto-renewed via Let's Encrypt.

## Private Networking (6PN)

All apps in an organization are connected via a WireGuard mesh using IPv6 (6PN). This is automatic and always on.

- Apps in the same org can communicate directly via 6PN addresses
- Apps in different orgs are isolated (no cross-org 6PN)
- 6PN bypasses Fly Proxy (no autostop/autostart; use Flycast for that)

**Binding to accept private connections**:
- Bind to `fly-local-6pn:<port>` or `[::]:<port>` (all interfaces)
- The 6PN address is aliased to `fly-local-6pn` in `/etc/hosts`
- `FLY_PRIVATE_IP` env var contains the Machine's 6PN address

**Important**: 6PN addresses are NOT static. They change on reboot/migration. Use `.internal` DNS names instead.

## Internal DNS

The Fly.io DNS server at `fdaa::3` resolves `.internal` domains for inter-app communication.

### AAAA Queries (Machine IPv6 addresses)

| Domain | Returns |
|---|---|
| `<appname>.internal` | All started Machines in any region |
| `<region>.<appname>.internal` | Machines in specific region |
| `<machine_id>.vm.<appname>.internal` | Specific Machine |
| `<process_group>.process.<appname>.internal` | Machines in process group |
| `top<N>.nearest.of.<appname>.internal` | N closest Machines |
| `global.<appname>.internal` | Alias for `<appname>.internal` |

### TXT Queries (Discovery)

| Domain | Returns |
|---|---|
| `_apps.internal` | All app names in org |
| `vms.<appname>.internal` | Machine IDs + regions (started only) |
| `all.vms.<appname>.internal` | Machine IDs + regions (all deployed) |
| `regions.<appname>.internal` | Regions with started Machines |
| `_instances.internal` | All started Machines in org (ID, app, IP, region) |

**Only started (running) Machines appear in AAAA queries.** Stopped/autostopped Machines are excluded.

Example usage from within a Machine:

```bash
dig +short aaaa my-db.internal                  # Find database app
dig +short aaaa iad.my-app.internal             # Machines in iad region
dig +short txt _apps.internal                   # List all apps in org
dig +short txt regions.my-app.internal          # Regions with running Machines
```

## Flycast (Private Proxy)

Flycast provides Fly Proxy features (load balancing, autostop/autostart) over the private network. Use Flycast instead of raw 6PN when you need:
- Autostop/autostart for internal services
- Load balancing across Machines
- Health check-based routing

```bash
fly ips allocate-v6 --private          # Allocate Flycast address
```

Flycast addresses are accessible only within the organization's private network. Remove public IPs from private apps (`fly ips release <ip>`) to prevent external access.

## Dynamic Request Routing

Use the `fly-replay` response header to replay requests to different regions, apps, or Machines:

```
# Route to a specific region
fly-replay: region=iad

# Route to a specific app
fly-replay: app=my-other-app

# Route to a specific Machine
fly-replay: instance=<machine-id>

# Route to a different app in a different region
fly-replay: region=ord;app=my-other-app
```

Your app returns `fly-replay` as a response header and Fly Proxy replays the request to the specified target. Useful for:
- Primary/replica database routing (write to primary region, read from nearest)
- Multi-tenant routing
- Sticky sessions

## WireGuard VPN

Connect your local machine to the Fly.io private network:

```bash
fly wireguard create                   # Generate WireGuard config
fly wireguard create my-org iad my-peer  # With specific org, region, peer name
fly wireguard list                     # List tunnels
fly wireguard remove                   # Remove a tunnel
```

Import the generated `.conf` file into your WireGuard client. Once connected:
- Access `.internal` DNS
- Connect directly to Machine 6PN addresses
- Useful for development/debugging against production private services

DNS on WireGuard: specified in the generated config file (e.g., `DNS = fdaa:0:18::3`). Pattern: org prefix + `::3`.

## Egress IPs

Outbound connections from Machines use IPv6 addresses that are NOT the Anycast IPs.

```bash
# Check outbound IP from within a Machine
echo $FLY_PUBLIC_IP

# Allocate static egress IP (billed monthly)
fly machine egress-ip allocate <machine-id>
fly machine egress-ip list
fly machine egress-ip release <egress-ip>
```

**Default**: Egress IPs are dynamic, may change on Machine migration. Do not allowlist them.

**Static egress IPs**: Per-machine, survives migration. Use when connecting to services requiring IP allowlisting. Prefer WireGuard when possible.
