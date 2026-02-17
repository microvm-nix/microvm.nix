# http-server Example

A fast-starting nginx web server demonstrating practical MicroVM deployment.

## Quick Start

```bash
# Build the example
nix build .#http-server

# Start the VM (runs in foreground, Ctrl+C to stop)
./result/bin/microvm-run

# In another terminal, test the HTTP server:
curl http://localhost:28080/
curl http://localhost:28080/health
curl http://localhost:28080/api/info
```

## Features

- **Fast boot**: ~7.9s boot-to-serve time (nginx responding to HTTP requests)
- **User-mode networking**: No root privileges required
- **Dual consoles**: Serial (ttyS0) for debug, virtio (hvc0) for interactive use
- **REST API**: Simple JSON endpoint demonstrating dynamic responses
- **Boot optimizations**: Disabled firewall, timesyncd, and resolved for faster startup

## Available Scripts

| Script | Description |
|--------|-------------|
| `microvm-run` | Start the VM |
| `microvm-shutdown` | Stop the VM gracefully |
| `run-test` | Run full automated test suite |
| `curl-test` | Quick HTTP connectivity check |
| `measure-boot` | Measure boot-to-serve time |
| `connect-serial` | Connect to ttyS0 (early boot) |
| `connect-console` | Connect to hvc0 (fast interactive) |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 28080 | TCP | HTTP (forwarded to guest port 80) |
| 4520 | TCP | Serial console (ttyS0) |
| 4521 | TCP | Virtio console (hvc0) |

## Endpoints

| Path | Response |
|------|----------|
| `/` | HTML welcome page |
| `/health` | `OK` (for health checks) |
| `/api/info` | JSON with hostname and timestamp |

## Architecture

```
Host                          Guest (MicroVM)
─────────────────────────────────────────────────
localhost:28080  ─────────►  nginx:80
localhost:4520   ─────────►  ttyS0 (serial)
localhost:4521   ─────────►  hvc0 (virtio)

Networking: QEMU SLIRP (user-mode)
```

## Testing

```bash
# Run automated tests
./result/bin/run-test

# Or via the test-all-examples runner
nix run .#test-all-examples -- http-server
```
