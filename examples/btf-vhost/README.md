# BTF + vhost MicroVM Example

A MicroVM demonstrating **BTF (BPF Type Format)** kernel support and **vhost-net** accelerated networking.

## Features

- **BTF-enabled kernel** - Run eBPF tools like `tcptop`, `execsnoop`, and `bpftrace` without recompilation
- **vhost-net acceleration** - High-throughput TAP networking (typically >5 Gbps)
- **Dual TCP consoles** - Both serial (ttyS0) and virtio-console (hvc0) accessible via TCP
- **Passwordless SSH** - Easy testing access (insecure, for development only)

## Quick Start

```bash
# Build the MicroVM
nix build .#btf-vhost

# Setup host networking (requires sudo)
./result/bin/microvm-setup-network

# Start the VM in background
./result/bin/microvm-run &

# Run automated tests
./result/bin/microvm-test
```

## Console Architecture

| Console | Port | Type | Use Case |
|---------|------|------|----------|
| ttyS0 | 4321 | Emulated 16550 UART | Early boot, kernel panics, debugging |
| hvc0 | 4322 | virtio-console | Interactive sessions (faster) |

Connect with: `nc localhost <port>` or use the helper scripts.

## Helper Scripts

| Script | Description |
|--------|-------------|
| `microvm-setup-network` | Create bridge and TAP interface (requires sudo) |
| `microvm-run` | Start the MicroVM |
| `microvm-ssh` | SSH into the VM (passwordless) |
| `microvm-console` | Connect to hvc0 (fast interactive console) |
| `microvm-serial` | Connect to ttyS0 (kernel/debug output) |
| `microvm-test` | Run automated connectivity and feature tests |
| `microvm-teardown-network` | Remove network interfaces |

## Testing BTF/eBPF

Once logged in (as root):

```bash
# TCP throughput by connection
tcptop

# Trace new process executions
execsnoop

# Custom tracing with bpftrace
bpftrace -e 'tracepoint:syscalls:sys_enter_* { @[probe] = count(); }'
```

## Testing Network Throughput

```bash
# On host
iperf -s

# In VM
iperf -c 10.90.0.1
```

## Network Configuration

| Interface | Address |
|-----------|---------|
| Host bridge (microvm-br0) | 10.90.0.1/24 |
| VM (eth0) | 10.90.0.2/24 |

## File Organization

```
btf-vhost/
├── default.nix       # Main entry point
├── config.nix        # Shared variables (IPs, ports, resources)
├── guest-config.nix  # Guest NixOS config (network, SSH, packages)
├── helper-scripts.nix # Helper scripts for bin/
├── qemu-consoles.nix # QEMU TCP console socket arguments
└── README.md         # This file
```

## Security Warning

This example is **intentionally insecure** for ease of testing:
- SSH allows root login with empty password
- No firewall restrictions beyond basic ports

**Do not use this configuration in production.**
