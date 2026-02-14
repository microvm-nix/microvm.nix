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
# Usage:
#   # Start waypipe client on host first:
#   nix run .#waypipe-client
#
#   # Then run the graphics VM:
#   nix run .#graphics -- <packages...>
#
#   # Example with Firefox:
#   nix run .#graphics -- firefox
#
# Features:
#   - Wayland display via waypipe/virtio-gpu
#   - XWayland support for X11 applications
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
  userConfig = import ./user-config.nix;
  waylandEnv = import ./wayland-env.nix;
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.microvm

    (
      { lib, pkgs, ... }:
      {
        # ════════════════════════════════════════════════════════════════════
        # MicroVM Configuration
        # ════════════════════════════════════════════════════════════════════
        microvm = {
          hypervisor = "cloud-hypervisor";
          graphics.enable = true;
          interfaces = lib.optional (tapInterface != null) {
            type = "tap";
            id = tapInterface;
            mac = "00:00:00:00:00:02";
          };
        };

        networking.hostName = "graphical-microvm";
        system.stateVersion = lib.trivial.release;
        nixpkgs.overlays = [ self.overlay ];

        # ════════════════════════════════════════════════════════════════════
        # User Configuration
        # ════════════════════════════════════════════════════════════════════
        services.getty.autologinUser = userConfig.username;
        users.users.${userConfig.username} = userConfig.userAttrs;
        users.groups.${userConfig.username} = { };
        security.sudo = userConfig.sudoConfig;

        # ════════════════════════════════════════════════════════════════════
        # Wayland Environment
        # ════════════════════════════════════════════════════════════════════
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

        # ════════════════════════════════════════════════════════════════════
        # Packages
        # ════════════════════════════════════════════════════════════════════
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
