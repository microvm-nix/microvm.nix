# examples/btf-vhost/default.nix
#
# Main entry point for the BTF + vhost MicroVM example.
#
# This example demonstrates:
# - BTF (BPF Type Format) kernel support for eBPF tools
# - vhost-net TAP networking for high throughput
# - TCP-accessible serial console (ttyS0) and virtio-console (hvc0)
#
# Console Architecture:
# +---------------------------------------------------------------------+
# | ttyS0 (TCP port 4321) - Emulated 16550 UART                         |
# |   - Available very early in boot (before virtio drivers load)       |
# |   - Captures kernel panic messages                                  |
# |   - Slower - each byte traps to hypervisor                          |
# |   - Use for: kernel console, debugging, early boot issues           |
# |   Connect: nc localhost 4321                                        |
# +---------------------------------------------------------------------+
# | hvc0 (TCP port 4322) - virtio-console                               |
# |   - Fast - native virtio, batched I/O                               |
# |   - Lower CPU overhead                                              |
# |   - Supports terminal resize                                        |
# |   - NOT available until virtio drivers load                         |
# |   - Use for: interactive login sessions                             |
# |   Connect: nc localhost 4322                                        |
# +---------------------------------------------------------------------+
#
# Security Note:
#   This example is INTENTIONALLY INSECURE for ease of testing.
#   SSH allows root login with no password. Do not use in production.
#
# Usage:
#   nix build .#btf-vhost
#   ./result/bin/microvm-setup-network  # Setup host networking (requires sudo)
#   ./result/bin/microvm-run &          # Start VM in background
#   ./result/bin/microvm-test           # Run connectivity tests
#   ./result/bin/microvm-ssh            # SSH into VM
#   ./result/bin/microvm-console        # Connect to hvc0 (fast)
#   ./result/bin/microvm-serial         # Connect to ttyS0 (debug)
#   ./result/bin/microvm-teardown-network  # Cleanup networking
#
# File Organization:
#   config.nix       - Shared configuration variables (IPs, ports, etc.)
#   qemu-consoles.nix - QEMU arguments for TCP console sockets
#   helper-scripts.nix - Helper scripts (setup, test, ssh, console, etc.)
#   guest-config.nix  - Guest NixOS configuration (network, SSH, packages)

{
  self,
  nixpkgs,
  system,
}:

let
  # Import shared configuration
  config = import ./config.nix;

  # Import QEMU console arguments
  qemuConsoleArgs = import ./qemu-consoles.nix { inherit config; };
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.microvm

    (
      {
        lib,
        pkgs,
        config,
        ...
      }:
      let
        # Import port/network config from shared constants
        portConfig = import ./config.nix;

        # Import helper scripts (needs pkgs)
        helperScripts = import ./helper-scripts.nix {
          pkgs = pkgs;
          config = portConfig;
        };

        # Import guest configuration (needs lib, pkgs, config)
        guestConfig = import ./guest-config.nix {
          inherit lib pkgs;
          config = portConfig;
        };

        # Hostname for this VM (used in process naming)
        hostName = "btf-vhost-microvm";
      in
      {
        system.stateVersion = lib.trivial.release;
        networking.hostName = hostName;

        # MicroVM Configuration

        # Enable BTF for eBPF tools
        microvm.kernelBtf = true;

        microvm = {
          hypervisor = "qemu";
          mem = portConfig.mem;
          vcpu = portConfig.vcpu;

          # TAP interface with vhost-net acceleration
          interfaces = [
            {
              type = "tap";
              id = portConfig.tapInterface;
              mac = portConfig.vmMac;
              tap.vhost = true;
            }
          ];

          # Disable default stdio serial - we use TCP sockets instead
          qemu.serialConsole = false;

          # Add TCP-accessible console arguments and process naming
          # Process name uses hostName for easy identification in ps output
          qemu.extraArgs = [
            "-name"
            "${hostName},process=${hostName}"
          ]
          ++ qemuConsoleArgs;

          # Add helper scripts to the runner package
          binScripts = helperScripts;
        };

        # Guest NixOS Configuration (imported from guest-config.nix)

        # Kernel console configuration
        boot.kernelParams = guestConfig.boot.kernelParams;

        # Getty services for login prompts
        systemd.services = guestConfig.systemd.services;

        # Network configuration
        systemd.network = guestConfig.systemd.network;
        networking.firewall.allowedTCPPorts = guestConfig.networking.firewall.allowedTCPPorts;

        # SSH configuration (INSECURE - for testing only)
        services.openssh = guestConfig.services.openssh;
        services.getty.autologinUser = guestConfig.services.getty.autologinUser;

        # User configuration
        users.users.root = guestConfig.users.users.root;
        users.motd = guestConfig.users.motd;

        # Security configuration
        security.pam.services.sshd.allowNullPassword =
          guestConfig.security.pam.services.sshd.allowNullPassword;

        # eBPF tools
        environment.systemPackages = guestConfig.environment.systemPackages;
      }
    )
  ];
}
