# valkey-server Example

A high-performance Valkey (Redis-compatible) server demonstrating fast MicroVM startup.

## Quick Start

```bash
# Build the example
nix build .#valkey-server

# Start the VM
./result/bin/microvm-run &

# Test Valkey
valkey-cli -p 16379 PING
valkey-cli -p 16379 SET greeting "Hello from MicroVM"
valkey-cli -p 16379 GET greeting
```

## Features

- **Fast boot**: ~7.7s boot-to-PONG time (Valkey responding to commands)
- **User-mode networking**: No root privileges required
- **Built-in benchmarking**: Measure ops/sec with included tools
- **Redis-compatible**: Drop-in replacement, same protocol
- **Boot optimizations**: Disabled firewall, timesyncd, and resolved for faster startup

## Available Scripts

| Script | Description |
|--------|-------------|
| `microvm-run` | Start the VM |
| `microvm-shutdown` | Stop the VM gracefully |
| `run-test` | Run full automated test suite |
| `valkey-test` | Quick PING/SET/GET test |
| `valkey-benchmark` | Run performance benchmark |
| `measure-boot` | Measure boot-to-PONG time |
| `connect-serial` | Connect to ttyS0 |
| `connect-console` | Connect to hvc0 |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 16379 | TCP | Valkey (forwarded to guest port 6379) |
| 4540 | TCP | Serial console (ttyS0) |
| 4541 | TCP | Virtio console (hvc0) |

## Architecture

```
Host                          Guest (MicroVM)
─────────────────────────────────────────────────
localhost:16379  ─────────►  valkey:6379
localhost:4540   ─────────►  ttyS0 (serial)
localhost:4541   ─────────►  hvc0 (virtio)

Networking: QEMU SLIRP (user-mode)
```

## Testing

```bash
# Run automated tests
./result/bin/run-test

# Run benchmark
./result/bin/valkey-benchmark

# Measure boot time
./result/bin/measure-boot
```
