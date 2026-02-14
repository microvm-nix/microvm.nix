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

## File Organization

```
graphics/
├── default.nix     # Main entry point
├── user-config.nix # User account settings
├── wayland-env.nix # Wayland environment variables
└── README.md       # This file
```
