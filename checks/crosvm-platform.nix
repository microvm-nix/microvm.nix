{ self, nixpkgs, system, ... }:

let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};
  makeConfig = modules: lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.microvm
      {
        networking.hostName = "crosvm-platform-test";
        system.stateVersion = "25.11";
        microvm = {
          hypervisor = "crosvm";
          vsock.cid = 77;
        };
      }
    ] ++ modules;
  };
  valid = makeConfig [
    {
      microvm = {
        crosvm.deviceTreeOverlays = [ "overlay file.dtbo" ];
        devices = [
          {
            bus = "platform";
            path = "6800000.ethernet test";
            crosvm = {
              dtSymbol = "mgbe0";
              mmioBase = 1711276032;
              mapEarly = true;
            };
          }
          {
            bus = "pci";
            path = "0000:01:00.0";
            crosvm = {
              guestAddress = "00:1f.0";
              iommu = "off";
            };
          }
        ];
      };
    }
  ];
  runner = import ../lib/runners/crosvm.nix {
    inherit pkgs;
    microvmConfig = valid.config.microvm;
    macvtapFds = { };
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };
  layout = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm.crosvm = {
        memoryBase = 137438953472;
        platformMmio = {
          base = 1610612736;
          size = 135828340736;
        };
      };
    }
  ];
  layoutRunner = import ../lib/runners/crosvm.nix {
    inherit pkgs;
    microvmConfig = layout.config.microvm;
    macvtapFds = { };
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };
  assertionsPass = nixos: builtins.all ({ assertion, ... }: assertion) nixos.config.assertions;
  protected = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm.crosvm.protection.mode = "protected-without-firmware";
    }
  ];
  protectedRunner = import ../lib/runners/crosvm.nix {
    inherit pkgs;
    microvmConfig = protected.config.microvm;
    macvtapFds = { };
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };
  protectedWithFirmware = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm.crosvm.protection = {
        mode = "protected-with-firmware";
        firmware = pkgs.writeText "test-pvmfw" "";
      };
    }
  ];
  protectedFirmwareRunner = import ../lib/runners/crosvm.nix {
    inherit pkgs;
    microvmConfig = protectedWithFirmware.config.microvm;
    macvtapFds = { };
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };
  protectedWithAssignedDevice = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm = {
        crosvm = {
          deviceTreeOverlays = [ "mgbe0.dtbo" ];
          protection = {
            mode = "protected-without-firmware";
            allowDeviceAssignment = true;
          };
        };
        devices = [
          {
            bus = "platform";
            path = "6800000.ethernet";
            crosvm = {
              dtSymbol = "mgbe0";
              iommu = "pkvm-iommu";
            };
          }
        ];
      };
    }
  ];
  protectedMissingFirmware = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm.crosvm.protection.mode = "protected-with-firmware";
    }
  ];
  protectedWithShare = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm = {
        crosvm.protection.mode = "protected-without-firmware";
        shares = [
          {
            tag = "test-share";
            source = "/tmp";
            mountPoint = "/tmp/shared";
            proto = "9p";
          }
        ];
      };
    }
  ];
  missingSymbol = makeConfig [
    {
      microvm = {
        crosvm.deviceTreeOverlays = [ "overlay.dtbo" ];
        devices = [{ bus = "platform"; path = "6800000.ethernet"; }];
      };
    }
  ];
  missingOverlay = makeConfig [
    {
      microvm.devices = [
        {
          bus = "platform";
          path = "6800000.ethernet";
          crosvm.dtSymbol = "mgbe0";
        }
      ];
    }
  ];
  unsupportedHypervisor = makeConfig [
    {
      microvm = {
        hypervisor = lib.mkForce "qemu";
        crosvm.deviceTreeOverlays = [ "overlay.dtbo" ];
      };
    }
  ];
  fixedPci = makeConfig [
    {
      microvm.devices = [
        {
          bus = "pci";
          path = "0000:01:00.0";
          crosvm.mmioBase = 1711276032;
        }
      ];
    }
  ];
  unsupportedLayout = makeConfig [
    {
      microvm.crosvm.memoryBase = 137438953472;
    }
  ];
  overlappingLayout = makeConfig [
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      microvm.crosvm = {
        memoryBase = 2147483648;
        platformMmio = {
          base = 2415919104;
          size = 268435456;
        };
      };
    }
  ];
in
lib.optionalAttrs (lib.hasSuffix "-linux" system) {
  crosvm-platform-devices =
    assert lib.hasInfix "--device-tree-overlay 'overlay file.dtbo'" runner.command;
    assert lib.hasInfix "'/sys/bus/platform/devices/6800000.ethernet test,iommu=off,dt-symbol=mgbe0,mmio-base=0x66000000,map-early=true'" runner.command;
    assert lib.hasInfix "/sys/bus/pci/devices/0000:01:00.0,iommu=off,guest-address=00:1f.0" runner.command;
    assert lib.hasInfix "--mem 'size=512,base=0x2000000000'" layoutRunner.command;
    assert lib.hasInfix "--platform-mmio 'base=0x60000000,size=0x1fa0000000'" layoutRunner.command;
    assert lib.hasInfix "--protected-vm-without-firmware --swiotlb 64" protectedRunner.command;
    assert lib.hasInfix "--protected-vm-with-firmware" protectedFirmwareRunner.command;
    assert !lib.hasInfix "--swiotlb" runner.command;
    assert lib.hasInfix (
      if pkgs.stdenv.hostPlatform.isAarch64 then "crosvm stop" else "crosvm powerbtn"
    ) runner.shutdownCommand;
    assert assertionsPass valid;
    assert assertionsPass layout;
    assert assertionsPass protected;
    assert assertionsPass protectedWithFirmware;
    assert assertionsPass protectedWithAssignedDevice;
    assert !assertionsPass missingSymbol;
    assert !assertionsPass missingOverlay;
    assert !assertionsPass unsupportedHypervisor;
    assert !assertionsPass fixedPci;
    assert !assertionsPass unsupportedLayout;
    assert !assertionsPass overlappingLayout;
    assert !assertionsPass protectedMissingFirmware;
    assert !assertionsPass protectedWithShare;
    pkgs.runCommand "crosvm-platform-devices" { } "touch $out";
}
