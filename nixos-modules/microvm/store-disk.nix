{ config, lib, pkgs, ... }:

let
  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  erofsFlags = builtins.concatStringsSep " " config.microvm.storeDiskErofsFlags;
  squashfsFlags = builtins.concatStringsSep " " config.microvm.storeDiskSquashfsFlags;

  mkfsCommand =
    {
      squashfs = "gensquashfs ${squashfsFlags} -D store --all-root -q $out";
      erofs = "mkfs.erofs ${erofsFlags} -T 0 --all-root -L nix-store --mount-point=/nix/store $out store";
    }.${config.microvm.storeDiskType};

  checkProbeCommand = lib.optionalString (config.microvm.storeDiskType == "erofs") /* bash */ ''
    echo Checking that the store disk is identified as erofs with LABEL=nix-store
    probe=$(blkid -p -o udev "$out")
    if ! grep -qx 'ID_FS_TYPE=erofs' <<<"$probe" ||
       ! grep -qx 'ID_FS_LABEL=nix-store' <<<"$probe"; then
      cat >&2 <<EOF
ERROR: blkid does not identify the store disk as erofs with LABEL=nix-store.

The guest mounts this disk through /dev/disk/by-label/nix-store,
so a failed probe leaves the VM without a nix store and drops it into the emergency shell,
where no TTY is attached.

This can be fixed by changing the configuration, eg: adding a new package

blkid reported:
EOF
      printf '%s\n' "''${probe:-<no output>}" | sed 's/^/  /' >&2
      exit 1
    fi
  '';

  writeClosure = pkgs.writeClosure or pkgs.writeReferencesToFile;

  storeDiskContents = writeClosure (
    [ config.system.build.toplevel ]
    ++
    lib.optional config.nix.enable regInfo
  );

in
{
  options.microvm.storeDisk = with lib; mkOption {
    type = types.path;
    description = ''
      Generated
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (config.microvm.guest.enable && config.microvm.storeOnDisk) {
      # nixos/modules/profiles/hardened.nix forbids erofs.
      # HACK: Other NixOS modules populate
      # config.boot.blacklistedKernelModules depending on the boot
      # filesystems, so checking on that directly would result in an
      # infinite recursion.
      microvm.storeDiskType = lib.mkDefault (
        if config.security.virtualisation.flushL1DataCache == "always"
        then "squashfs"
        else "erofs"
      );
      boot.initrd.availableKernelModules = [
        config.microvm.storeDiskType
      ];

      microvm.storeDisk = pkgs.buildPackages.runCommandLocal "microvm-store-disk.${config.microvm.storeDiskType}" {
        nativeBuildInputs = with pkgs.buildPackages; [
          time
          bubblewrap
          util-linux
          {
            squashfs = squashfs-tools-ng;
            erofs = erofs-utils;
          }.${config.microvm.storeDiskType}
        ];
        passthru = {
          inherit regInfo;
        };
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      } ''
        mkdir store
        BWRAP_ARGS="--dev-bind / / --chdir $(pwd)"
        for d in $(sort -u ${storeDiskContents}); do
          BWRAP_ARGS="$BWRAP_ARGS --ro-bind $d $(pwd)/store/$(basename $d)"
        done

        echo Creating a ${config.microvm.storeDiskType}
        bwrap $BWRAP_ARGS -- time ${mkfsCommand} || \
          (
            echo "Bubblewrap failed. Falling back to copying...">&2
            cp -a $(sort -u ${storeDiskContents}) store/
            time ${mkfsCommand}
          )

        ${checkProbeCommand}
      '';
    })

    (lib.mkIf (config.microvm.registerClosure && config.nix.enable) {
      microvm.kernelParams = [
        "regInfo=${regInfo}/registration"
      ];
      boot.postBootCommands = ''
        if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
          ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
        fi
      '';
    })
  ];
}
