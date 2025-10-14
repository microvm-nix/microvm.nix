{ config, lib, ... }:

let
  inherit (config.microvm) storeDiskType storeOnDisk writableStoreOverlay;

  inherit (import ../../lib {
    inherit lib;
  }) defaultFsType withDriveLetters;

  hostStore = builtins.head (
    builtins.filter ({ source, ... }:
      source == "/nix/store"
    ) config.microvm.shares
  );

  roStore =
    if storeOnDisk
    then "/nix/.ro-store"
    else hostStore.mountPoint;

  roStoreDisk =
    if storeOnDisk
    then
      if storeDiskType == "erofs"
      # erofs supports filesystem labels
      then "/dev/disk/by-label/nix-store"
      else "/dev/vda"
    else throw "No disk letter when /nix/store is not in disk";

  # Check if the writable store overlay is a virtiofs share
  isRwStoreVirtiofsShare = builtins.any ({mountPoint, proto, ... }:
    mountPoint == config.microvm.writableStoreOverlay
    && proto == "virtiofs"
  ) config.microvm.shares;

in
lib.mkIf config.microvm.guest.enable {
  fileSystems = lib.mkMerge [ (
    # built-in read-only store without overlay
    lib.optionalAttrs (
      storeOnDisk &&
      writableStoreOverlay == null
    ) {
      "/nix/store" = {
        device = roStoreDisk;
        fsType = storeDiskType;
        options = [ "x-systemd.requires=systemd-modules-load.service" ];
        neededForBoot = true;
        noCheck = true;
      };
    }
  ) (
    # host store is mounted somewhere else,
    # bind-mount to the proper place
    lib.optionalAttrs (
      !storeOnDisk &&
      config.microvm.writableStoreOverlay == null &&
      hostStore.mountPoint != "/nix/store"
    ) {
      "/nix/store" = {
        device = hostStore.mountPoint;
        options = [ "ro" "bind" ];
        neededForBoot = true;
      };
    }
  ) (
    # built-in read-only store for the overlay
    lib.optionalAttrs (
      storeOnDisk &&
      writableStoreOverlay != null
    ) {
      "/nix/.ro-store" = {
        device = roStoreDisk;
        fsType = storeDiskType;
        options = [ "ro" "x-systemd.requires=systemd-modules-load.service" ];
        neededForBoot = true;
        noCheck = true;
      };
    }
  ) (
    # mount store with writable overlay
    lib.optionalAttrs (writableStoreOverlay != null) {
      "/nix/store" = {
        neededForBoot = true;
        overlay = {
          lowerdir = [ roStore ];
          upperdir = "${writableStoreOverlay}/store";
          workdir = "${writableStoreOverlay}/work";
        };
        options = lib.optional isRwStoreVirtiofsShare "userxattr";
      };
    }
  ) {
    # a tmpfs / by default. can be overwritten.
    "/" = lib.mkDefault {
      device = "rootfs";
      fsType = "tmpfs";
      options = [ "size=50%,mode=0755" ];
      neededForBoot = true;
    };
  } (
    # Volumes
    builtins.foldl' (result: { label, mountPoint, letter, fsType ? defaultFsType, ... }:
      result // lib.optionalAttrs (mountPoint != null) {
        "${mountPoint}" = {
          inherit fsType;
          # Prioritize identifying a device by label if provided. This
          # minimizes the risk of misidentifying a device.
          device = if label != null then
            "/dev/disk/by-label/${label}"
          else
            "/dev/vd${letter}";
        } // lib.optionalAttrs (mountPoint == config.microvm.writableStoreOverlay) {
          neededForBoot = true;
        };
      }) {} (withDriveLetters config.microvm)
  ) (
    # 9p/virtiofs Shares
    builtins.foldl' (result: { mountPoint, tag, proto, source, ... }: result // {
      "${mountPoint}" = {
        device = tag;
        fsType = proto;
        options = {
          "virtiofs" = [ "defaults" "x-systemd.requires=systemd-modules-load.service" ];
          "9p" = [ "trans=virtio" "version=9p2000.L" "msize=65536" "x-systemd.requires=systemd-modules-load.service" ];
        }.${proto};
      } // lib.optionalAttrs (source == "/nix/store" || mountPoint == config.microvm.writableStoreOverlay) {
        neededForBoot = true;
      };
    }) {} config.microvm.shares
  ) ];
}
