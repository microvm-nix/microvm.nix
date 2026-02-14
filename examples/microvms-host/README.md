# MicroVMs Host Example

A MicroVM that hosts nested MicroVMs - one for each supported hypervisor.

## Purpose

This example demonstrates:
- The microvm.nix **host module** for declarative VM management
- **Nested virtualization** (MicroVMs inside a MicroVM)
- Testing all hypervisors in an isolated environment

## Platform Support

Hypervisors are automatically filtered by platform:
- **Linux:** qemu, cloud-hypervisor, firecracker, crosvm, kvmtool, stratovirt, alioth
- **macOS:** qemu, vfkit

Note: vfkit requires Apple's Virtualization.framework (macOS only).

## Architecture

```
Your Host Machine
└── microvms-host (QEMU, 8GB RAM, 4 vCPUs)
      │
      ├── virbr0 (10.0.0.1/24, DHCP server)
      │
      ├── qemu-microvm (10.0.0.2)
      ├── cloud-hypervisor-microvm (10.0.0.3)
      ├── firecracker-microvm (10.0.0.4)
      ├── crosvm-microvm (10.0.0.5)
      └── ... (all supported hypervisors)
```

## Quick Start

```bash
# Run the host VM
nix run .#vm

# Once booted, check nested VM status
networkctl status virbr0

# SSH into a nested VM (password: toor)
ssh root@qemu
ssh root@cloud-hypervisor
ssh root@firecracker
```

## Network Configuration

| Interface | Address | Purpose |
|-----------|---------|---------|
| virbr0 | 10.0.0.1/24 | Bridge for nested VMs |
| virbr0 | fd12:3456:789a::1/64 | IPv6 prefix |

Nested VMs receive addresses via DHCP starting from 10.0.0.2.

## Nested VM Access

Each nested VM:
- Has SSH enabled
- Root password: `toor`
- Hostname matches hypervisor name (e.g., `qemu-microvm`)

## Requirements

- Host must support nested virtualization
- QEMU is used for the outer VM (required for user networking)
- 8GB RAM allocated to host VM

## File Organization

```
microvms-host/
├── default.nix      # Main entry point
├── network-config.nix # MAC/IP address generation
├── nested-vms.nix   # Nested VM configurations
└── README.md        # This file
```
