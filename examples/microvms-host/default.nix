# examples/microvms-host/default.nix
#
# MicroVM that hosts nested MicroVMs.
#
# This example demonstrates the microvm.nix host module by creating a MicroVM
# that itself runs multiple nested MicroVMs - one for each supported hypervisor.
#
# This is useful for:
#   - Testing all hypervisors in an isolated environment
#   - Demonstrating nested virtualization capabilities
#   - CI/CD testing of microvm.nix itself
#
# Architecture:
#   Host (your machine)
#     └── microvms-host (QEMU with nested virt)
#           ├── qemu-microvm
#           ├── cloud-hypervisor-microvm
#           ├── firecracker-microvm
#           ├── crosvm-microvm
#           └── ... (all supported hypervisors)
#
# Note: Some hypervisors are platform-specific:
#   - vfkit: macOS only (uses Apple Virtualization.framework)
#   - Most others: Linux only (require KVM)
#
# Usage:
#   nix run .#vm
#
# Once booted, view nested VM DHCP leases:
#   networkctl status virbr0
#
# SSH into nested VMs (password: toor):
#   ssh root@<hypervisor-name>

{
  self,
  nixpkgs,
  system,
}:

let
  lib = nixpkgs.lib;

  # Get all hypervisors and filter by current system
  allHypervisors = self.lib.hypervisors;

  # Filter hypervisors to only those supported on the current system:
  # - vfkit: macOS only (requires Apple Virtualization.framework)
  # - Others: Linux only (require KVM)
  isDarwin = lib.hasSuffix "-darwin" system;
  hypervisors = builtins.filter (
    hv:
    if hv == "vfkit" then
      isDarwin # vfkit only works on macOS
    else
      !isDarwin # KVM-based hypervisors only work on Linux
  ) allHypervisors;

  networkConfig = import ./network-config.nix { inherit hypervisors; };
  nestedVms = import ./nested-vms.nix { inherit self hypervisors networkConfig; };
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # For declarative MicroVM management
    self.nixosModules.host
    # This itself runs as a MicroVM
    self.nixosModules.microvm

    (
      { config, lib, ... }:
      {
        networking.hostName = "microvms-host";
        system.stateVersion = lib.trivial.release;

        # ════════════════════════════════════════════════════════════════════
        # User Configuration
        # ════════════════════════════════════════════════════════════════════
        users.users.root.password = "";
        users.motd = ''
          Once nested MicroVMs have booted you can look up DHCP leases:
          networkctl status virbr0

          They are configured to allow SSH login with root password:
          toor
        '';
        services.getty.autologinUser = "root";

        # Make alioth available
        nixpkgs.overlays = [ self.overlay ];

        # ════════════════════════════════════════════════════════════════════
        # Host MicroVM Configuration
        # ════════════════════════════════════════════════════════════════════
        # This VM uses QEMU because nested virtualization and user networking
        # are required to run MicroVMs inside it.
        microvm = {
          mem = 8192;
          vcpu = 4;
          hypervisor = "qemu";
          interfaces = [
            {
              type = "user";
              id = "qemu";
              mac = "02:00:00:01:01:01";
            }
          ];
        };

        # ════════════════════════════════════════════════════════════════════
        # Nested MicroVMs (one per hypervisor)
        # ════════════════════════════════════════════════════════════════════
        microvm.vms = nestedVms;

        # ════════════════════════════════════════════════════════════════════
        # Network Configuration (bridge for nested VMs)
        # ════════════════════════════════════════════════════════════════════
        systemd.network = {
          enable = true;

          # Create bridge for nested VM networking
          netdevs.virbr0.netdevConfig = {
            Kind = "bridge";
            Name = "virbr0";
          };

          networks.virbr0 = {
            matchConfig.Name = "virbr0";

            addresses = [
              { Address = "10.0.0.1/24"; }
              { Address = "fd12:3456:789a::1/64"; }
            ];

            # DHCP server for nested VMs
            networkConfig = {
              DHCPServer = true;
              IPv6SendRA = true;
            };

            # Static DHCP leases for predictable addressing
            dhcpServerStaticLeases = lib.imap0 (i: hypervisor: {
              MACAddress = networkConfig.macAddrs.${hypervisor};
              Address = networkConfig.ipv4Addrs.${hypervisor};
            }) hypervisors;

            # IPv6 SLAAC
            ipv6Prefixes = [ { Prefix = "fd12:3456:789a::/64"; } ];
          };

          # Attach VM TAP interfaces to bridge
          networks.microvm-eth0 = {
            matchConfig.Name = "vm-*";
            networkConfig.Bridge = "virbr0";
          };
        };

        networking = {
          # Add hostnames for easy SSH access
          extraHosts = lib.concatMapStrings (hypervisor: ''
            ${networkConfig.ipv4Addrs.${hypervisor}} ${hypervisor}
          '') hypervisors;

          # Allow DHCP server
          firewall.allowedUDPPorts = [ 67 ];

          # NAT for internet access from nested VMs
          nat = {
            enable = true;
            enableIPv6 = true;
            internalInterfaces = [ "virbr0" ];
          };
        };
      }
    )
  ];
}
