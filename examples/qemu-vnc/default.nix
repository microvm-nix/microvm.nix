# examples/qemu-vnc/default.nix
#
# QEMU MicroVM with VNC graphical output.
#
# This example demonstrates running a graphical desktop (XFCE) inside a MicroVM,
# accessible via VNC. Useful for testing GUI applications in an isolated environment.
#
# Prerequisites:
#   mkdir /tmp/share  # Required shared directory
#
# Usage:
#   nix run .#qemu-vnc
#   # Then connect with a VNC client:
#   nix shell nixpkgs#tigervnc -c vncviewer localhost:5900
#
# Features:
#   - XFCE desktop environment
#   - VNC server on port 5900
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
  # Import sub-configurations
  qemuArgs = import ./qemu-args.nix;
  userConfig = import ./user-config.nix;
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
          hypervisor = "qemu";
          graphics.enable = true;
          interfaces = lib.optional (tapInterface != null) {
            type = "tap";
            id = tapInterface;
            mac = "00:00:00:00:00:02";
          };
          qemu.extraArgs = qemuArgs;
        };

        networking.hostName = "qemu-vnc";
        system.stateVersion = lib.trivial.release;

        # ════════════════════════════════════════════════════════════════════
        # User Configuration
        # ════════════════════════════════════════════════════════════════════
        services.getty.autologinUser = userConfig.username;
        users.users.${userConfig.username} = userConfig.userAttrs;
        users.groups.${userConfig.username} = { };
        security.sudo = userConfig.sudoConfig;

        # ════════════════════════════════════════════════════════════════════
        # Desktop Environment
        # ════════════════════════════════════════════════════════════════════
        services.xserver = {
          enable = true;
          desktopManager.xfce.enable = true;
          displayManager.autoLogin.user = userConfig.username;
        };

        hardware.graphics.enable = true;

        # ════════════════════════════════════════════════════════════════════
        # Packages
        # ════════════════════════════════════════════════════════════════════
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
