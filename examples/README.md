# MicroVM Examples

This directory contains example MicroVM configurations demonstrating various features and use cases.

## Overview

| Example | Description | Hypervisor | Key Features |
|---------|-------------|------------|--------------|
| [console-demo](./console-demo/README.md) | Learn serial vs virtio-console | QEMU | TCP consoles, ttyS0/hvc0 comparison, minimal |
| [btf-vhost](./btf-vhost/README.md) | eBPF/BTF development environment | QEMU | BTF kernel, vhost-net, TCP consoles, passwordless SSH |
| [microvms-host](./microvms-host/README.md) | Nested MicroVMs for testing | QEMU | Host module, nested virtualization, all hypervisors |
| [qemu-vnc](./qemu-vnc/README.md) | Graphical desktop via VNC | QEMU | XFCE desktop, VNC server, QXL graphics |
| [graphics](./graphics/README.md) | Wayland graphics passthrough | cloud-hypervisor | virtio-gpu, waypipe, native Wayland |

## Quick Start

```bash
# Run any example
nix run .#<example-name>

# Examples:
nix run .#console-demo
nix run .#btf-vhost
nix run .#vm           # microvms-host
nix run .#qemu-vnc
nix run .#graphics -- firefox
```

## Example Details

### [console-demo](./console-demo/README.md)
A minimal example teaching how Linux consoles work in MicroVMs.
- **Dual consoles** - serial (ttyS0) and virtio-console (hvc0)
- **TCP sockets** - connect with netcat while VM runs in background
- **Educational** - detailed comments explaining the architecture
- **Minimal** - just bash, no networking complexity

### [btf-vhost](./btf-vhost/README.md)
A development environment for eBPF/BTF tools with high-performance networking.
- **BTF-enabled kernel** for running `tcptop`, `execsnoop`, `bpftrace`
- **vhost-net acceleration** for multi-gigabit throughput
- **Dual TCP consoles** (serial + virtio) for flexible access
- **Automated test suite** to verify all features

### [microvms-host](./microvms-host/README.md)
A MicroVM that itself hosts nested MicroVMs - one per supported hypervisor.
- **Demonstrates the host module** for declarative VM management
- **Tests all hypervisors** in an isolated environment
- **Platform-aware** - automatically filters by OS (Linux/macOS)
- **DHCP networking** with predictable addresses

### [qemu-vnc](./qemu-vnc/README.md)
A graphical XFCE desktop accessible via VNC.
- **Full desktop environment** running inside MicroVM
- **VNC access** on port 5900
- **Dynamic packages** - specify additional apps on command line

### [graphics](./graphics/README.md)
Native Wayland graphics using virtio-gpu passthrough.
- **waypipe integration** for seamless host display
- **XWayland support** for X11 applications
- **Low-latency graphics** via virtio-gpu

## Standalone Example

### [no-flake-microvm.nix](./no-flake-microvm.nix)
Demonstrates using microvm.nix without flakes. Useful for traditional Nix setups or understanding the module structure.

## File Organization

Each example directory follows a consistent structure:

```
<example>/
├── default.nix      # Main entry point
├── README.md        # Documentation
└── *.nix            # Supporting configuration modules
```

## Platform Support

| Hypervisor | Linux | macOS |
|------------|-------|-------|
| qemu | ✓ | ✓ (HVF) |
| cloud-hypervisor | ✓ | - |
| firecracker | ✓ | - |
| crosvm | ✓ | - |
| kvmtool | ✓ | - |
| stratovirt | ✓ | - |
| alioth | ✓ | - |
| vfkit | - | ✓ |

## Creating Your Own

Use these examples as templates for your own MicroVMs:

1. Copy an example directory
2. Modify `config.nix` (if present) for your settings
3. Adjust `default.nix` for your requirements
4. Add to your flake's apps or packages

See the [main documentation](../doc/src/SUMMARY.md) for detailed configuration options.
