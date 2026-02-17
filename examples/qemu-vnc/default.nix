# examples/qemu-vnc/default.nix
#
# QEMU MicroVM with VNC graphical output.
#
# This example demonstrates running a graphical desktop (XFCE) inside a MicroVM,
# accessible via VNC. Includes serial console for automated testing.
#
# Prerequisites:
#   mkdir /tmp/share  # Required shared directory
#
# Usage:
#   nix build .#qemu-vnc
#   ./result/bin/microvm-run &
#   ./result/bin/run-test              # Run automated tests
#   ./result/bin/connect-serial        # Connect to serial console
#   # Or connect with a VNC client:
#   nix shell nixpkgs#tigervnc -c vncviewer localhost:5900
#
# Features:
#   - XFCE desktop environment
#   - VNC server on port 5900
#   - Serial console on port 4500 (for testing)
#   - Optional TAP networking
#   - Dynamic package installation via command line

{
  self,
  nixpkgs,
  system,
  packages ? "",
  tapInterface ? null,
}:

let
  # Import configuration from centralized constants
  config = import ./config.nix;

  # Import sub-configurations
  qemuArgs = import ./qemu-args.nix { inherit config; };
  userConfig = import ./user-config.nix;

  # Import test library
  testLib = nixpkgs.legacyPackages.${system}.callPackage ../lib/test-lib.nix { inherit config; };
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.microvm

    (
      { lib, pkgs, ... }:
      let
        # Hostname for this VM (used in process naming)
        hostName = "qemu-vnc";

        # Test library with pkgs bound
        testLibPkgs = import ../lib/test-lib.nix { inherit pkgs config; };
      in
      {
        # MicroVM Configuration
        microvm = {
          hypervisor = "qemu";
          mem = config.mem;
          vcpu = config.vcpu;
          # VNC is manually configured via extraArgs, not through graphics module
          # graphics.enable = true adds GTK+GL display which conflicts with VNC
          graphics.enable = false;
          # Use q35 machine type for VGA support (microvm machine type doesn't support VGA)
          qemu.machine = "q35";
          interfaces = lib.optional (tapInterface != null) {
            type = "tap";
            id = tapInterface;
            mac = "00:00:00:00:00:02";
          };

          # Disable default stdio serial - we use TCP sockets instead
          qemu.serialConsole = false;

          # Add VNC, serial console, and process naming
          qemu.extraArgs = [
            "-name"
            "${hostName},process=${hostName}"
          ]
          ++ qemuArgs;

          # Helper scripts for testing
          binScripts = {
            run-test = testLibPkgs.makeTestScript {
              name = "qemu-vnc";
              extraTests = ''
                # ─────────────────────────────────────────────────────────────────
                echo "Testing VNC port availability..."
                # ─────────────────────────────────────────────────────────────────
                if ${pkgs.netcat}/bin/nc -z localhost ${toString config.vncPort} 2>/dev/null; then
                  pass "VNC port ${toString config.vncPort} is listening"
                else
                  fail "VNC port ${toString config.vncPort} is not available"
                fi
              '';
            };
            connect-serial = testLibPkgs.makeSerialConnectScript;
            console-status = testLibPkgs.makeConsoleStatusScript;
          };
        };

        networking.hostName = hostName;
        system.stateVersion = lib.trivial.release;

        # Serial Console Configuration (for automated testing)
        # Add kernel console output to serial
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

        # User Configuration
        services.getty.autologinUser = userConfig.username;
        users.users.${userConfig.username} = userConfig.userAttrs;
        users.groups.${userConfig.username} = { };
        security.sudo = userConfig.sudoConfig;

        # Empty root password for serial testing
        users.users.root.password = "";

        # Desktop Environment
        services.xserver = {
          enable = true;
          desktopManager.xfce.enable = true;
          displayManager.autoLogin.user = userConfig.username;
        };

        hardware.graphics.enable = true;

        # Packages
        # Includes xdg-utils (required) plus any packages specified via CLI
        environment.systemPackages =
          with pkgs;
          [
            xdg-utils
          ]
          ++ map (
            package:
            lib.attrByPath (lib.splitString "." package) (throw "Package ${package} not found in nixpkgs") pkgs
          ) (builtins.filter (package: package != "") (lib.splitString " " packages));
      }
    )
  ];
}
