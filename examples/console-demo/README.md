# Console Demo MicroVM

A minimal MicroVM demonstrating the dual console architecture with TCP socket backends.

## Purpose

This example teaches you how Linux console devices work in a MicroVM:

- **ttyS0 (serial)** - Emulated 16550 UART, available immediately at boot
- **hvc0 (virtio-console)** - Paravirtualized console, fast but requires drivers

Both consoles are exposed via TCP sockets, allowing you to connect while the VM runs in the background.

## Quick Start

```bash
# Build the example
nix build .#console-demo

# Run automated test (starts VM, tests consoles, shuts down)
./result/bin/run-test

# Or manually:
./result/bin/microvm-run &        # Start VM in background
./result/bin/console-status       # Check console ports
./result/bin/connect-serial       # Watch boot (ttyS0)
./result/bin/connect-console      # Interactive shell (hvc0)
./result/bin/microvm-shutdown     # Shutdown VM
```

## Console Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          MicroVM Guest                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Kernel ──────────► /dev/ttyS0 ──────────► getty (login)           │
│     │                    │                                          │
│     │                    │ (16550 UART emulation)                   │
│     │                    ▼                                          │
│     │              ┌──────────┐     TCP Socket                      │
│     │              │  QEMU    │ ◄──────────────► localhost:4440     │
│     │              └──────────┘                                     │
│     │                                                               │
│     └──────────► /dev/hvc0 ───────────► getty (login)               │
│                      │                                              │
│                      │ (virtio-serial + virtconsole)                │
│                      ▼                                              │
│              ┌──────────────┐   TCP Socket                          │
│              │ virtio-serial│ ◄────────────► localhost:4441         │
│              └──────────────┘                                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Serial vs Virtio-Console

| Aspect | ttyS0 (Serial) | hvc0 (Virtio-Console) |
|--------|----------------|----------------------|
| **Type** | Emulated 16550 UART | Paravirtualized (virtio) |
| **Speed** | Slow (per-byte traps) | Fast (batched I/O) |
| **Availability** | Immediate | After virtio drivers load |
| **Kernel panics** | Captured | May be lost |
| **Terminal resize** | No | Yes (SIGWINCH) |
| **Use case** | Boot debug, crashes | Interactive sessions |

## How It Works

### Kernel Command Line

```
console=ttyS0,115200 console=hvc0
```

- First `console=` directs early boot to serial
- Last `console=` becomes `/dev/console` (primary)
- Both receive kernel messages initially

### QEMU Configuration

```
# Serial (ttyS0)
-chardev socket,id=serial0,host=localhost,port=4440,server=on,wait=off
-serial chardev:serial0

# Virtio-console (hvc0)
-device virtio-serial-device
-chardev socket,id=virtcon0,host=localhost,port=4441,server=on,wait=off
-device virtconsole,chardev=virtcon0
```

## Exploring Consoles

Once logged in, try these commands:

```bash
# See which consoles are registered
cat /proc/consoles

# Check console= kernel parameters
dmesg | grep -i console

# See the TTY you're connected to
tty

# Write to the other console
echo "Hello from $(tty)" > /dev/ttyS0
echo "Hello from $(tty)" > /dev/hvc0
```

## File Organization

```
console-demo/
├── default.nix       # Main entry point
├── config.nix        # Port configuration
├── qemu-consoles.nix # QEMU arguments with detailed comments
└── README.md         # This file
```

## TCP Ports

| Console | Port | Connect |
|---------|------|---------|
| ttyS0 (serial) | 4440 | `nc localhost 4440` |
| hvc0 (virtio) | 4441 | `nc localhost 4441` |
