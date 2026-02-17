# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

microvm.nix is a Nix Flake for building and running NixOS MicroVMs on Type-2 hypervisors. It supports 8 hypervisors (qemu, cloud-hypervisor, firecracker, crosvm, kvmtool, stratovirt, alioth, vfkit) across Linux and macOS.

## Build and Test Commands

```bash
# Run example MicroVMs
nix run .#qemu-example
nix run .#firecracker-example
nix run .#cloud-hypervisor-example

# Run all checks (comprehensive test matrix)
nix flake check

# Run automated example tests (see examples/README.md for details)
nix run .#test-all-examples           # Run all example tests
nix run .#test-all-examples-repeat    # Run 3 times (catch flaky failures)

# Build documentation
nix build .#doc

# Build all prebuilt packages (for CI cache)
nix build .#prebuilt
```

## Architecture

```
flake.nix
    │
    ├── nix/                    # Flake component imports
    │   ├── apps.nix            # App definitions (examples)
    │   ├── packages.nix        # Package outputs
    │   ├── overlays.nix        # Nixpkgs overlays
    │   └── examples/           # Example configurations
    │
    ├── nixos-modules/
    │   ├── microvm/            # Guest VM configuration
    │   │   ├── options.nix     # All guest options (main reference)
    │   │   ├── system.nix      # Kernel, boot, systemd setup
    │   │   └── ...
    │   └── host/               # Host VM management
    │       ├── default.nix     # Systemd services for VM lifecycle
    │       └── options.nix     # Host options
    │
    └── lib/
        ├── runner.nix          # Orchestrates runner package creation
        ├── runners/*.nix       # Hypervisor-specific command generation
        ├── volumes.nix         # Volume creation utilities
        └── default.nix         # Exports hypervisors list, helper functions
                │
                ▼
        Output: Runner Package
        ├── bin/microvm-run
        ├── bin/microvm-shutdown
        └── share/microvm/*
```

**Data Flow**: User config → NixOS module evaluates options → runner.nix builds package → hypervisor-specific runner generates CLI commands → executable scripts output.

## Key Files

- `flake.nix` - Entry point, imports from `nix/` directory
- `nix/` - Flake components (apps.nix, packages.nix, overlays.nix, examples/)
- `nixos-modules/microvm/options.nix` - All guest configuration options (main reference)
- `nixos-modules/host/default.nix` - Host systemd service templates
- `lib/runners/qemu.nix` - Most feature-complete hypervisor implementation (reference for others)
- `lib/default.nix` - Exports hypervisors list (note: vfkit is macOS only)
- `checks/default.nix` - Test matrix generation

## Examples Structure

Examples are organized in `examples/` with each as a directory. See [examples/README.md](./examples/README.md) for full documentation including automated testing.

```
examples/
├── README.md              # Overview, testing docs, port allocations
├── lib/                   # Shared test infrastructure
│   ├── constants.nix      # Centralized port allocations
│   ├── test-lib.nix       # Test script generators
│   └── *.nix              # Console and getty configs
├── btf-vhost/             # eBPF/BTF + vhost networking
│   ├── default.nix        # Entry point
│   ├── config.nix         # Imports from lib/constants.nix
│   ├── guest-config.nix   # NixOS guest configuration
│   ├── helper-scripts.nix # bin/ scripts (setup, test, ssh)
│   └── qemu-consoles.nix  # QEMU console arguments
├── microvms-host/         # Nested MicroVMs (one per hypervisor)
│   ├── default.nix        # Entry point (filters hypervisors by OS)
│   ├── config.nix         # Imports from lib/constants.nix
│   ├── network-config.nix # MAC/IP address generation
│   └── nested-vms.nix     # Per-hypervisor VM configs
├── qemu-vnc/              # VNC graphical desktop
├── graphics/              # Wayland graphics passthrough
└── run-all-tests.nix      # Test runner for all examples
```

Apps are defined in `nix/apps.nix` and reference `examples/<name>/default.nix`.

### Running Example Tests

```bash
# Run all example tests
nix run .#test-all-examples

# Run tests 3 times (catch intermittent failures)
nix run .#test-all-examples-repeat

# Test individual example
nix build .#console-demo && ./result/bin/run-test
```

## Adding New Options

Pattern follows existing options like `tap.vhost` or `kernelBtf`:

1. **Define option** in `nixos-modules/microvm/options.nix`:
```nix
myOption = mkOption {
  type = types.bool;
  default = false;
  description = ''Description here'';
};
```

2. **Implement behavior** in relevant module (e.g., `system.nix` for kernel, runner files for hypervisor args)

3. **Use conditionally**:
```nix
lib.optionals config.microvm.myOption [ ... ]
```

4. **Update docs** in `doc/src/options.md` and `README.md`

## Hypervisor Capabilities

| Hypervisor | 9p | virtiofs | Control Socket | Platform |
|------------|----|---------:|----------------|----------|
| qemu | ✓ | ✓ | ✓ | Linux |
| cloud-hypervisor | ✗ | ✓ | ✓ | Linux |
| firecracker | ✗ | ✗ | ✓ | Linux |
| crosvm | broken | ✓ | ✓ | Linux |
| kvmtool | ✓ | ✗ | ✗ | Linux |
| stratovirt | ✗ | ✗ | ✗ | Linux |
| alioth | ✗ | ✗ | ✗ | Linux |
| vfkit | ✗ | ✓ | ✓ | macOS |

When adding features, check `lib/runners/*.nix` for hypervisor-specific implementation patterns.

## CI/CD

- `.github/workflows/prebuilt-*.yml` - Build and cache packages
- `.github/workflows/doc.yml` - Build and deploy documentation
- `checks/default.nix` - Test matrix covering hypervisors × storage configs × boot methods

## Nix Patterns Used

- `lib.mkIf` for conditional configuration
- `lib.mkOption` with `types.*` for option definitions
- `lib.kernel.yes/no/module` for kernel config options
- `writeShellScript` for generated scripts in runner packages
- `builtins.listToAttrs` + `lib.concatMap` for dynamic attribute generation

## Important: Never Use --impure

**Never use `--impure` with nix commands.** All builds must be pure and reproducible.

```bash
# WRONG - never do this
nix build --impure .#something
nix run --impure .#something

# CORRECT - pure builds only
nix build .#something
nix run .#something
```

If a build requires `--impure`, that indicates a design problem that needs to be fixed properly (e.g., missing inputs, hardcoded paths, or environment dependencies).
