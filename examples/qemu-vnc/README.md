# QEMU VNC MicroVM Example

A MicroVM with a graphical XFCE desktop accessible via VNC.

## Quick Start

```bash
# Create required shared directory
mkdir /tmp/share

# Build and run the MicroVM
nix build .#qemu-vnc
./result/bin/microvm-run &

# Connect with VNC (in another terminal)
nix shell nixpkgs#tigervnc -c vncviewer localhost:5900

# Run automated tests
./result/bin/run-test
```

## Features

- **XFCE desktop** - Lightweight, full-featured desktop environment
- **VNC access** - Connect from any VNC client on port 5900
- **Serial console** - TCP console on port 4500 for automated testing
- **Standard VGA** - Compatible with all QEMU builds
- **Optional networking** - TAP interface support

## Port Allocations

| Service | Port |
|---------|------|
| VNC     | 5900 |
| Serial  | 4500 |

## Adding Packages

Specify additional packages on the command line:

```bash
nix run .#qemu-vnc -- firefox chromium
```

## With TAP Networking

```bash
nix run .#qemu-vnc -- --tap tap0 firefox
```

## User Account

- **Username:** user
- **Password:** (empty)
- **Sudo:** passwordless

## File Organization

```
qemu-vnc/
├── default.nix     # Main entry point
├── config.nix      # Centralized constants (ports, memory)
├── qemu-args.nix   # VNC and input device arguments
├── user-config.nix # User account settings
└── README.md       # This file
```

## Configuration Issues and Fixes

This example required several configuration adjustments to work properly with VNC
and automated testing. These fixes address incompatibilities between VNC display
mode and the default microvm.nix graphics configuration.

### Issue 1: VNC/GL Display Conflict

**Initial State**: The original configuration had `graphics.enable = true`.

**Error**:
```
qemu: -vnc :0: Display vnc is incompatible with the GL context
```

**Root Cause**: When `graphics.enable = true`, the microvm.nix runner adds:
```
-display gtk,gl=on -device virtio-vga-gl
```
This GTK+GL display configuration conflicts with VNC which cannot use GL contexts.

**Fix Applied**: Set `graphics.enable = false` since we configure VNC manually via
`extraArgs`. Comment in code explains the rationale:
```nix
microvm = {
  # VNC is manually configured via extraArgs, not through graphics module
  # graphics.enable = true adds GTK+GL display which conflicts with VNC
  graphics.enable = false;
};
```

### Issue 2: VGA Not Supported on microvm Machine Type

**Initial State**: Using default `microvm` machine type.

**Error**:
```
microvm@qemu-vnc: warning: A -vga option was passed but this machine type does not use that option
```

**Root Cause**: The default `microvm` machine type is a minimal QEMU machine that
doesn't support traditional VGA devices. It's designed for virtio-only configurations.

**Fix Applied**: Use the `q35` machine type which is a full PC emulation with VGA
support:
```nix
microvm = {
  # Use q35 machine type for VGA support (microvm machine type doesn't support VGA)
  qemu.machine = "q35";
};
```

### Issue 3: QXL VGA Not Available in Minimal QEMU

**Initial State**: Using `-vga qxl` for optimized virtualization graphics.

**Error**:
```
microvm@qemu-vnc: QXL VGA not available
```

**Root Cause**: The optimized `qemu-host-cpu-only` QEMU build used by microvm.nix
doesn't include QXL support. QXL requires additional SPICE libraries that are
omitted from the minimal build.

**Fix Applied**: Use standard VGA (`-vga std`) instead of QXL, which is always
available in all QEMU builds. In `qemu-args.nix`:
```nix
# Standard VGA (compatible with all QEMU builds including minimal ones)
"-vga"
"std"
```

### Summary of Required Configuration

The working configuration requires these three settings:

| Setting | Value | Reason |
|---------|-------|--------|
| `graphics.enable` | `false` | Avoids GTK+GL conflict with VNC |
| `qemu.machine` | `"q35"` | Uses machine type that supports VGA |
| `-vga` | `std` | Uses universally available VGA adapter |

## Testing

The automated test (`run-test`) verifies:
- Serial port connectivity (port 4500)
- System boot and shell responsiveness
- VNC port availability (port 5900)

```bash
./result/bin/run-test
```
