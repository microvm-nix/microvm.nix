{ config, lib, pkgs, ... }:

let
  microvm-lib = import ../../lib {
    inherit lib;
  };

in

{
  imports = [
    ./boot-disk.nix
    ./store-disk.nix
    ./options.nix
    ./asserts.nix
    ./system.nix
    ./mounts.nix
    ./interfaces.nix
    ./pci-devices.nix
    ./virtiofsd
    ./graphics.nix
    ./rosetta.nix
    ./optimization.nix
    ./ssh-deploy.nix
    ./vsock-ssh.nix
  ];

  config = {
    microvm.runner = lib.genAttrs microvm-lib.hypervisors (hypervisor:
      microvm-lib.buildRunner {
        inherit pkgs;
        microvmConfig = config.microvm // {
          inherit (config.networking) hostName;
          inherit hypervisor;
        };
        inherit (config.system.build) toplevel;
      }
    );

    # Set /etc/machine-id from machineId if provided
    # This ensures the guest machine-id matches the UUID passed to machined and SMBIOS
    environment.etc."machine-id" = lib.mkIf (config.microvm.machineId != null) {
      text = builtins.replaceStrings ["-"] [""] config.microvm.machineId + "\n";
    };
  };
}
