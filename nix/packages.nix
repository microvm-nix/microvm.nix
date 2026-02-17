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

  # Helper to convert example directories to runner packages
  # These are the advanced examples in examples/ directory
  exampleToRunner =
    configFile:
    (import configFile {
      inherit self nixpkgs system;
    }).config.microvm.declaredRunner;

  # Advanced example runners (exposed as packages for testing)
  # Note: graphics example requires packages argument, built with empty default
  advancedExamples = lib.optionalAttrs (lib.hasSuffix "-linux" system) {
    btf-vhost = exampleToRunner ../examples/btf-vhost;
    console-demo = exampleToRunner ../examples/console-demo;
    qemu-vnc = exampleToRunner ../examples/qemu-vnc;
    http-server = exampleToRunner ../examples/http-server;
    valkey-server = exampleToRunner ../examples/valkey-server;
    graphics =
      (import ../examples/graphics {
        inherit self nixpkgs system;
        packages = "";
        tapInterface = null;
      }).config.microvm.declaredRunner;
    microvms-host =
      (import ../examples/microvms-host {
        inherit self nixpkgs system;
      }).config.microvm.declaredRunner;
  };
in
advancedExamples
// {
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
