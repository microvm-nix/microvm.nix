# Flake package definitions
{
  self,
  nixpkgs,
  system,
}:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ self.overlay ];
  };

  inherit (pkgs) lib;
in
{
  build-microvm = pkgs.callPackage ../pkgs/build-microvm.nix { inherit self; };
  doc = pkgs.callPackage ../pkgs/doc.nix { };
  microvm = import ../pkgs/microvm-command.nix {
    pkgs = import nixpkgs { inherit system; };
  };

  # all compilation-heavy packages that shall be prebuilt for a binary cache
  prebuilt = pkgs.buildEnv {
    name = "prebuilt";
    paths =
      with self.packages.${system};
      with pkgs;
      [
        qemu-example
        cloud-hypervisor-example
        firecracker-example
        crosvm-example
        kvmtool-example
        stratovirt-example
        # alioth-example
        virtiofsd
      ];
    pathsToLink = [ "/" ];
    extraOutputsToInstall = [ "dev" ];
    ignoreCollisions = true;
  };
}
//
  # wrap self.nixosConfigurations in executable packages
  lib.listToAttrs (
    lib.concatMap (
      configName:
      let
        config = self.nixosConfigurations.${configName};
        packageName = lib.replaceString "${system}-" "" configName;
        # Check if this config's guest system matches our current build system
        # (accounting for darwin hosts building linux guests)
        guestSystem = config.pkgs.stdenv.hostPlatform.system;
        buildSystem = lib.replaceString "-darwin" "-linux" system;
      in
      lib.optional (guestSystem == buildSystem) {
        name = packageName;
        value = config.config.microvm.runner.${config.config.microvm.hypervisor};
      }
    ) (builtins.attrNames self.nixosConfigurations)
  )
