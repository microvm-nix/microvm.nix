# MicroVM Examples

This directory contains example MicroVM configurations demonstrating various features and use cases.

## Overview

| Example | Description | Hypervisor | Key Features |
|---------|-------------|------------|--------------|
| [console-demo](./console-demo/README.md) | Learn serial vs virtio-console | QEMU | TCP consoles, ttyS0/hvc0 comparison, minimal |
| [http-server](./http-server/README.md) | Fast-starting nginx web server | QEMU | Boot-to-serve time, user-mode networking, REST API |
| [valkey-server](./valkey-server/README.md) | High-performance Valkey cache | QEMU | Sub-second startup, benchmarking, Redis-compatible |
| [btf-vhost](./btf-vhost/README.md) | eBPF/BTF development environment | QEMU | BTF kernel, vhost-net, TCP consoles, passwordless SSH |
| [microvms-host](./microvms-host/README.md) | Nested MicroVMs for testing | QEMU | Host module, nested virtualization, all hypervisors |
| [qemu-vnc](./qemu-vnc/README.md) | Graphical desktop via VNC | QEMU | XFCE desktop, VNC server, q35 machine |
| [graphics](./graphics/README.md) | Wayland graphics passthrough | cloud-hypervisor | virtio-gpu, waypipe, native Wayland |

## Quick Start

```bash
# Run any example
nix run .#<example-name>

# Examples:
nix run .#console-demo
nix run .#http-server    # then: curl localhost:28080
nix run .#valkey-server  # then: valkey-cli -p 16379 PING
nix run .#btf-vhost
nix run .#vm             # microvms-host
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

### [http-server](./http-server/README.md)
A fast-starting nginx web server demonstrating practical application deployment.
- **~7.9s boot-to-serve** - nginx responds to HTTP requests
- **User-mode networking** - no root required, port 28080
- **REST API endpoint** - simple JSON response at /api/info
- **Boot optimizations** - disabled firewall, timesyncd, resolved

### [valkey-server](./valkey-server/README.md)
A high-performance Valkey (Redis-compatible) server demonstrating database workloads.
- **~7.7s boot-to-serve** - Valkey responds to PING
- **Built-in benchmarking** - measure ops/sec with valkey-benchmark
- **User-mode networking** - no root required, port 16379
- **Boot optimizations** - disabled firewall, timesyncd, resolved

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

## Automated Testing

All examples include automated tests accessible via `run-test` scripts. Tests verify:
- VM starts successfully
- Console ports become accessible
- System boots and shell responds
- Example-specific functionality works

### Run All Tests

```bash
# Run all standard tests (console-demo, http-server, valkey-server, qemu-vnc)
nix run .#test-all-examples

# Run specific examples
nix run .#test-all-examples -- console-demo qemu-vnc

# Run tests multiple times (catch intermittent failures)
nix run .#test-all-examples-repeat
```

**Example output:**
```
╔═══════════════════════════════════════════════════════════════╗
║           MicroVM Examples - Test Suite                       ║
╚═══════════════════════════════════════════════════════════════╝

Pre-flight: Checking port availability...
  ✓ All ports available

Running tests sequentially...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Testing: console-demo
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...
✓ console-demo passed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Testing: qemu-vnc
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...
✓ qemu-vnc passed

═══════════════════════════════════════════════════════════════
                         Summary
═══════════════════════════════════════════════════════════════
Passed: console-demo qemu-vnc
All tests passed!
```

### Run Individual Tests

```bash
# Build an example
nix build .#console-demo

# Run the automated test
./result/bin/run-test

# Connect to serial console manually
./result/bin/connect-serial

# Check port status
./result/bin/console-status
```

**Example output for console-demo:**
```
════════════════════════════════════════════════════════════════
              Console Demo - Automated Test
════════════════════════════════════════════════════════════════

1. Starting MicroVM...
  • VM started with PID 12345
2. Waiting for console ports to be available...
  ✓ Serial port 4440 is listening
  ✓ Virtio port 4441 is listening
3. Waiting for system to boot (polling for shell response)...
  ✓ System booted and shell is responsive
4. Testing serial console (ttyS0) on port 4440...
  ✓ Serial console responds to echo command
5. Testing virtio console (hvc0) on port 4441...
  ✓ Virtio console (hvc0) responds to echo command
6. Running 'ps ax' via virtio console...
  ✓ ps ax executed successfully
7. Checking /proc/consoles in guest...
  ✓ ttyS0 registered in /proc/consoles
  ✓ hvc0 registered in /proc/consoles
8. Testing hostname command via serial console...
  ✓ Serial console returns correct hostname: console-demo
9. Shutting down VM...
  ✓ VM shutdown complete

════════════════════════════════════════════════════════════════
Console demo test completed successfully!
════════════════════════════════════════════════════════════════
```

**Example output for qemu-vnc:**
```
╔═══════════════════════════════════════════════════════════════╗
║        qemu-vnc - Automated Test Suite
╚═══════════════════════════════════════════════════════════════╝

1. Checking if ports are available...
  ✓ Serial port 4500 is available
2. Starting MicroVM...
  • VM started with PID 12345
3. Waiting for serial port...
  ✓ Serial port 4500 is listening (1s)
5. Waiting for system boot (testing shell response)...
  ✓ System booted and shell is responsive (3s)
6. Testing serial console command execution...
  ✓ Serial console responds: uname -r
Testing VNC port availability...
  ✓ VNC port 5900 is listening
7. Shutting down VM...

═══════════════════════════════════════════════════════════════
All tests passed!
```

### Test Runner Options

```bash
# Run tests in parallel (faster but uses more resources)
nix run .#test-all-examples -- --parallel

# Skip pre-flight port check (useful when ports are in TIME_WAIT)
nix run .#test-all-examples -- --skip-preflight

# Show available examples and their ports
nix run .#test-all-examples -- --help
```

### Cleaning Up Stale VMs

If you get port conflicts from previous test runs:

```bash
# Kill stale MicroVM processes and check port availability
nix run .#cleanup-vms
```

**Example output:**
```
Cleaning up stale MicroVM processes...
  ✓ Killed QEMU processes
  • Waiting for ports to be released...
All example ports are available.
```

Then run your tests:
```bash
nix run .#test-all-examples
```

**Note:** The cleanup script only kills microvm.nix processes (matching `microvm@`).
If ports are used by other VMs (e.g., libvirt), you can either:
- Stop those VMs first
- Run specific tests that don't conflict: `nix run .#test-all-examples -- console-demo`
- Use `--skip-preflight` if you're sure the ports will be available when the test runs

### Testing Notes

**Self-contained tests** (console-demo, http-server, valkey-server, qemu-vnc): These tests start the VM, run checks, and shut down automatically.

**btf-vhost**: Requires network setup before testing. Run the VM manually, execute `setup-network`, then run `microvm-test`. See [btf-vhost/README.md](./btf-vhost/README.md) for details.

**graphics, microvms-host**: Require special setup (waypipe client, nested virtualization). Not included in default test suite.

### Port Allocations

Each example uses unique ports for concurrent testing:

| Example | Serial (ttyS0) | Virtio (hvc0) | VNC | Service |
|---------|----------------|---------------|-----|---------|
| btf-vhost | 4321 | 4322 | - | - |
| console-demo | 4440 | 4441 | - | - |
| http-server | 4520 | 4521 | - | 28080 (HTTP) |
| valkey-server | 4540 | 4541 | - | 16379 (Valkey) |
| qemu-vnc | 4500 | - | 15900 | - |
| graphics | - | - | 15901 | - |
| microvms-host | 4480 | - | - | - |

Port allocations are centralized in `lib/constants.nix`.

### Boot Time Performance

The `http-server` and `valkey-server` examples achieve **~7.7 second boot-to-serve** times with optimizations applied.

**Measured boot times:**
| Example | Boot-to-serve |
|---------|---------------|
| http-server | 7.88s |
| valkey-server | 7.65s |

**Boot time breakdown (via `systemd-analyze`):**
| Phase | Time | Notes |
|-------|------|-------|
| Kernel | ~240ms | Linux kernel initialization |
| Initrd | ~2.5s | **Largest component (60%)** - future optimization target |
| Userspace | ~1.5s | systemd services |
| **Total** | ~4.2s | Inside VM (add ~3.5s QEMU startup for full time) |

**Optimizations applied:**
- Disabled `firewall.service` - saves ~500ms
- Disabled `systemd-timesyncd` - saves ~270ms
- Disabled `systemd-resolved` - saves ~200ms (using static DNS via QEMU SLIRP at 10.0.2.3)

**Known slow components (future optimization):**
- **Initrd** (~2.5s): The initial ramdisk is the largest boot time contributor. Direct kernel boot without initrd could potentially halve boot time.
- **Device enumeration** (~2.8s): Waiting for serial (ttyS0) and disk devices to appear. This is QEMU/kernel device discovery.

Run `systemd-analyze blame` inside a VM to see service timing on your hardware.

### Test Scripts

Each example provides these helper scripts in `result/bin/`:

| Script | Description |
|--------|-------------|
| `microvm-run` | Start the VM |
| `microvm-shutdown` | Stop the VM gracefully |
| `run-test` | Automated test suite |
| `connect-serial` | Connect to ttyS0 serial console |
| `console-status` | Check if console ports are listening |

## File Organization

Each example directory follows a consistent structure:

```
<example>/
├── default.nix      # Main entry point
├── config.nix       # Configuration (imports from lib/constants.nix)
├── README.md        # Documentation
└── *.nix            # Supporting configuration modules
```

### Shared Library

Common test infrastructure is in `lib/`:

```
lib/
├── constants.nix               # Port allocations for all examples
├── test-lib.nix                # Test script generators
├── qemu-serial-console.nix     # QEMU ttyS0 TCP socket args
├── qemu-virtio-console.nix     # QEMU hvc0 TCP socket args
├── guest-serial-getty.nix      # Guest getty config for ttyS0
├── guest-virtio-getty.nix      # Guest getty config for hvc0
├── socket-console.nix          # Unix socket console support
├── cloud-hypervisor-console.nix # cloud-hypervisor console args
├── file-console.nix            # File-based console output
└── vnc-screenshot.nix          # VNC capture/compare utilities
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
