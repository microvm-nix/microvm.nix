# examples/graphics/default.nix
#
# Wayland graphics MicroVM with virtio-gpu passthrough.
#
# This example demonstrates running Wayland applications inside a MicroVM
# using virtio-gpu for graphics and waypipe for display forwarding.
#
# The VM connects to a waypipe client running on the host via AF_VSOCK,
# allowing native Wayland applications to display on the host's compositor.
#
# Console Testing:
#   This example uses file-based console testing. cloud-hypervisor defaults
#   to --serial tty (serial output to stdout). The test script redirects
#   stdout to a log file and polls for "login:" boot marker.
#
# Usage:
#   # Start waypipe client on host first:
#   nix run .#waypipe-client
#
#   # Then run the graphics VM:
#   nix build .#graphics
#   ./result/bin/microvm-run              # Interactive (console in terminal)
#   ./result/bin/run-test                 # Run automated tests
#
#   # Or run with specific packages:
#   nix run .#graphics -- firefox
#
# Features:
#   - Wayland display via waypipe/virtio-gpu
#   - XWayland support for X11 applications
#   - File-based console testing (stdout redirect)
#   - Dynamic package installation via command line
#   - Optional TAP networking

{
  self,
  nixpkgs,
  system,
  packages ? "",
  tapInterface ? null,
}:

let
  # Import configuration from centralized constants
  portConfig = import ./config.nix;

  userConfig = import ./user-config.nix;
  waylandEnv = import ./wayland-env.nix;
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.microvm

    (
      { lib, pkgs, ... }:
      let
        # Hostname for this VM (used for process identification)
        hostName = "graphical-microvm";

        # Import file-based console testing library
        fileConsole = import ../lib/file-console.nix {
          inherit pkgs;
          config = portConfig;
        };
      in
      {
        # MicroVM Configuration
        microvm = {
          hypervisor = "cloud-hypervisor";
          mem = portConfig.mem;
          vcpu = portConfig.vcpu;
          graphics.enable = true;
          interfaces = lib.optional (tapInterface != null) {
            type = "tap";
            id = tapInterface;
            mac = "00:00:00:00:00:02";
          };

          # No extraArgs needed - use cloud-hypervisor defaults:
          #   --serial tty    (serial output to stdout)
          #   --console null  (virtio-console disabled)
          # The test script redirects stdout to capture serial output.

          # Helper scripts for testing
          binScripts = {
            # Test script using file-based console (stdout redirect)
            run-test = fileConsole.makeFileConsoleTestScript {
              name = "graphics";
              processPattern = "cloud-hypervisor";
            };

            # Console info script
            console-info = fileConsole.makeFileConsoleInfoScript;
          };
        };

        networking.hostName = hostName;
        system.stateVersion = lib.trivial.release;
        nixpkgs.overlays = [ self.overlay ];

        # Console Configuration (for testing via file output)
        # Direct kernel output to serial (ttyS0)
        # cloud-hypervisor defaults to --serial tty (stdout)
        boot.kernelParams = [
          "console=ttyS0"
        ];

        # Run getty on serial console for shell access
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

        # Empty password for console testing
        users.users.root.password = "";

        # Wayland Environment
        environment.sessionVariables = waylandEnv;

        # Wayland proxy service - connects to host via AF_VSOCK
        systemd.user.services.wayland-proxy = {
          enable = true;
          description = "Wayland Proxy";
          serviceConfig = with pkgs; {
            ExecStart = "${wayland-proxy-virtwl}/bin/wayland-proxy-virtwl --virtio-gpu --x-display=0 --xwayland-binary=${xwayland}/bin/Xwayland";
            Restart = "on-failure";
            RestartSec = 5;
          };
          wantedBy = [ "default.target" ];
        };

        hardware.graphics.enable = true;

        # Packages
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
