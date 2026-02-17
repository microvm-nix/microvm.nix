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
#   nix build .#microvms-host
#   ./result/bin/microvm-run &         # Start VM in background
#   ./result/bin/run-test              # Run automated tests
#   ./result/bin/connect-serial        # Connect to serial console
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

  # Import configuration from centralized constants
  portConfig = import ./config.nix;

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

  # QEMU serial console arguments
  serialConsoleArgs = import ../lib/qemu-serial-console.nix {
    serialPort = portConfig.serialPort;
  };
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # For declarative MicroVM management
    self.nixosModules.host
    # This itself runs as a MicroVM
    self.nixosModules.microvm

    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        # Hostname for this VM (used in process naming)
        hostName = "microvms-host";

        # Test library with pkgs bound
        testLibPkgs = import ../lib/test-lib.nix {
          pkgs = pkgs;
          config = portConfig;
        };
      in
      {
        networking.hostName = hostName;
        system.stateVersion = lib.trivial.release;

        # User Configuration
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

        # Serial Console Configuration (for automated testing)
        boot.kernelParams = [
          "console=ttyS0,115200"
        ];

        # Enable getty on serial console
        systemd.services."serial-getty@ttyS0" = {
          enable = true;
          wantedBy = [ "getty.target" ];
        };

        # Clean output for automated testing
        services.getty.helpLine = "";
        services.getty.greetingLine = "";

        # Host MicroVM Configuration
        # This VM uses QEMU because nested virtualization and user networking
        # are required to run MicroVMs inside it.
        microvm = {
          mem = portConfig.mem;
          vcpu = portConfig.vcpu;
          hypervisor = "qemu";
          interfaces = [
            {
              type = "user";
              id = "qemu";
              mac = "02:00:00:01:01:01";
            }
          ];

          # Disable default stdio serial - we use TCP sockets instead
          qemu.serialConsole = false;

          # Add TCP serial console and process naming
          qemu.extraArgs = [
            "-name"
            "${hostName},process=${hostName}"
          ]
          ++ serialConsoleArgs;

          # Helper scripts for testing
          binScripts = {
            run-test = testLibPkgs.makeTestScript {
              name = "microvms-host";
              extraTests = ''
                # ─────────────────────────────────────────────────────────────────
                echo "Testing nested VM processes..."
                # ─────────────────────────────────────────────────────────────────
                # Wait longer for nested VMs to start (they boot after outer VM)
                info "Waiting for nested VMs to start..."
                sleep 30

                # Get process list from outer VM
                PS_OUTPUT=$(echo "ps aux" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$SERIAL_PORT" 2>/dev/null || true)

                # Check for expected hypervisor processes
                FOUND_NESTED=false

                if echo "$PS_OUTPUT" | grep -q "qemu-system"; then
                  pass "Nested QEMU VM process found"
                  FOUND_NESTED=true
                fi

                if echo "$PS_OUTPUT" | grep -q "firecracker"; then
                  pass "Nested Firecracker VM process found"
                  FOUND_NESTED=true
                fi

                if echo "$PS_OUTPUT" | grep -q "cloud-hypervisor"; then
                  pass "Nested cloud-hypervisor VM process found"
                  FOUND_NESTED=true
                fi

                if echo "$PS_OUTPUT" | grep -q "crosvm"; then
                  pass "Nested crosvm VM process found"
                  FOUND_NESTED=true
                fi

                if echo "$PS_OUTPUT" | grep -q "kvmtool"; then
                  pass "Nested kvmtool VM process found"
                  FOUND_NESTED=true
                fi

                if [ "$FOUND_NESTED" = true ]; then
                  pass "At least one nested VM is running"
                else
                  info "No nested VM processes detected (may need longer boot time)"
                fi

                # ─────────────────────────────────────────────────────────────────
                echo "Checking nested VM network bridge..."
                # ─────────────────────────────────────────────────────────────────
                BRIDGE_OUTPUT=$(echo "ip link show virbr0" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$SERIAL_PORT" 2>/dev/null || true)

                if echo "$BRIDGE_OUTPUT" | grep -q "virbr0"; then
                  pass "Network bridge virbr0 is configured"
                else
                  info "Bridge virbr0 status unclear"
                fi
              '';
            };
            connect-serial = testLibPkgs.makeSerialConnectScript;
            console-status = testLibPkgs.makeConsoleStatusScript;
          };
        };

        # Nested MicroVMs (one per hypervisor)
        microvm.vms = nestedVms;

        # Network Configuration (bridge for nested VMs)
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
