# Wayland Graphics MicroVM Example

A MicroVM with Wayland graphics using virtio-gpu and waypipe for display forwarding.

## Quick Start

```bash
# Start waypipe client on host first
nix run .#waypipe-client

# Run the graphics VM with desired applications
nix run .#graphics -- firefox
```

## How It Works

1. **Host side:** `waypipe-client` listens on AF_VSOCK for Wayland connections
2. **Guest side:** `wayland-proxy-virtwl` connects via virtio-gpu and forwards Wayland protocol
3. **Result:** Guest applications render natively on host compositor

## Features

- **Native Wayland** - Applications run with full Wayland support
- **XWayland** - X11 applications work via XWayland compatibility
- **virtio-gpu** - Hardware-accelerated graphics virtualization
- **Unix socket console** - Testing via socat (hvc0)
- **Dynamic packages** - Specify applications on command line

## Running Applications

```bash
# Single application
nix run .#graphics -- firefox

# Multiple applications
nix run .#graphics -- firefox chromium mpv

# With TAP networking
nix run .#graphics -- --tap tap0 firefox
```

## User Account

- **Username:** user
- **Password:** (empty)
- **Sudo:** passwordless

## Environment Variables

The following are set for Wayland compatibility:

| Variable | Value | Purpose |
|----------|-------|---------|
| WAYLAND_DISPLAY | wayland-1 | Wayland socket |
| DISPLAY | :0 | XWayland display |
| QT_QPA_PLATFORM | wayland | Qt apps |
| GDK_BACKEND | wayland | GTK apps |
| XDG_SESSION_TYPE | wayland | Electron apps |
| SDL_VIDEODRIVER | wayland | SDL apps |

## Automated Testing

This example uses a **Unix domain socket** for console testing because
cloud-hypervisor doesn't support TCP serial sockets like QEMU.

### Running Tests

```bash
nix build .#graphics
./result/bin/run-test           # Full automated test
./result/bin/connect-console    # Interactive console
./result/bin/console-status     # Check socket availability
```

### Console Access

The VM's console (hvc0) is accessible via Unix socket:

```bash
# While VM is running:
socat - UNIX-CONNECT:/tmp/microvm-graphical-microvm-console.sock
```

### What the Test Verifies

1. Socket cleanup from previous runs
2. VM starts successfully
3. Console socket becomes available
4. Shell responds to commands (boot detection)
5. cloud-hypervisor process is running
6. Clean shutdown via console

### Unix Socket vs TCP

| Aspect | Unix Socket | TCP |
|--------|-------------|-----|
| Tool | socat | netcat |
| Path/Port | `/tmp/microvm-*.sock` | localhost:PORT |
| Conflicts | None (unique paths) | Port collisions |
| Performance | Faster | Network overhead |
| Supported by | cloud-hypervisor | QEMU |

## Waypipe Testing (Future Work)

Full graphical verification of waypipe would require additional infrastructure:

| Approach | Description | Status |
|----------|-------------|--------|
| **Nested Test VM** | Weston headless in outer VM | Not implemented |
| **Protocol Capture** | `WAYLAND_DEBUG=1` comparison | Not implemented |
| **Mock Server** | Accept vsock, verify handshake | Not implemented |

The current console-based testing verifies the VM boots and shell is responsive,
which is sufficient for most CI/CD use cases.

See [TEST-AUTOMATION-PLAN.md](../../docs/TEST-AUTOMATION-PLAN.md) for details.

## File Organization

```
graphics/
├── default.nix     # Main entry point
├── config.nix      # Configuration (imports from lib/constants.nix)
├── user-config.nix # User account settings
├── wayland-env.nix # Wayland environment variables
└── README.md       # This file
```
