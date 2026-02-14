# Flake app definitions
{
  self,
  nixpkgs,
  system,
}:

let
  pkgs = nixpkgs.legacyPackages.${system};

  nixosToApp = configFile: {
    type = "app";
    program = "${
      (import configFile {
        inherit self nixpkgs system;
      }).config.microvm.declaredRunner
    }/bin/microvm-run";
  };
in
{
  vm = nixosToApp ../examples/microvms-host;
  qemu-vnc = nixosToApp ../examples/qemu-vnc;
  btf-vhost = nixosToApp ../examples/btf-vhost;
  console-demo = nixosToApp ../examples/console-demo;

  graphics = {
    type = "app";
    program = toString (
      pkgs.writeShellScript "run-graphics" ''
        set -e

        if [ -z "$*" ]; then
          echo "Usage: $0 [--tap tap0] <pkgs...>"
          exit 1
        fi

        if [ "$1" = "--tap" ]; then
          TAP_INTERFACE="\"$2\""
          shift 2
        else
          TAP_INTERFACE=null
        fi

        ${pkgs.nix}/bin/nix run \
          -f ${../examples/graphics} \
          config.microvm.declaredRunner \
          --arg self 'builtins.getFlake "${self}"' \
          --arg system '"${system}"' \
          --arg nixpkgs 'builtins.getFlake "${nixpkgs}"' \
          --arg packages "\"$*\"" \
          --arg tapInterface "$TAP_INTERFACE"
      ''
    );
  };

  # Run this on your host to accept Wayland connections on AF_VSOCK.
  waypipe-client = {
    type = "app";
    program = toString (
      pkgs.writeShellScript "waypipe-client" ''
        exec ${pkgs.waypipe}/bin/waypipe --vsock -s 6000 client
      ''
    );
  };
}
