# QEMU VNC MicroVM Example

A MicroVM with a graphical XFCE desktop accessible via VNC.

## Quick Start

```bash
# Create required shared directory
mkdir /tmp/share

# Run the MicroVM
nix run .#qemu-vnc

# Connect with VNC (in another terminal)
nix shell nixpkgs#tigervnc -c vncviewer localhost:5900
```

## Features

- **XFCE desktop** - Lightweight, full-featured desktop environment
- **VNC access** - Connect from any VNC client on port 5900
- **QXL graphics** - Optimized virtual graphics adapter
- **Optional networking** - TAP interface support

## Adding Packages

Specify additional packages on the command line:

```bash
nix run .#graphics -- firefox chromium
```

## With TAP Networking

```bash
nix run .#graphics -- --tap tap0 firefox
```

## User Account

- **Username:** user
- **Password:** (empty)
- **Sudo:** passwordless

## File Organization

```
qemu-vnc/
├── default.nix    # Main entry point
├── qemu-args.nix  # VNC and input device arguments
├── user-config.nix # User account settings
└── README.md      # This file
```
