{ config, lib, pkgs, ... }:

let
  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  erofs-utils =
    # Is deduplication option specified?
    if lib.elem "-Ededupe" config.microvm.storeDiskErofsFlags
    then
      # If specified, stick to the single-threaded erofs-utils
      # to not scare anyone with warning messages. mkfs.erofs
      # has no multi-threaded -Ededupe, so it forces
      # single-threaded compression.
      pkgs.buildPackages.erofs-utils
    else
      # Otherwise rebuild mkfs.erofs with multi-threading.
      pkgs.buildPackages.erofs-utils.overrideAttrs (attrs: {
        configureFlags = attrs.configureFlags ++ [
          "--enable-multithreading"
        ];
      });

  erofsFlags = builtins.concatStringsSep " " config.microvm.storeDiskErofsFlags;
  squashfsFlags = builtins.concatStringsSep " " config.microvm.storeDiskSquashfsFlags;

  mkfsCommand =
    {
      squashfs = "gensquashfs ${squashfsFlags} -D store --all-root -q $out";
      erofs = "mkfs.erofs ${erofsFlags} -T 0 --all-root -L nix-store --mount-point=/nix/store $out store";
    }.${config.microvm.storeDiskType};

  # The guest mounts the erofs store disk through /dev/disk/by-label/nix-store,
  # so udev has to identify the image unambiguously. libblkid probes for short
  # magic values at fixed offsets, and erofs keeps its inode count as a
  # little-endian 64-bit value at 0x410 -- the exact offset where MINIX v1/v2
  # expects its 16-bit magic. A closure whose inode count happens to collide
  # therefore probes as minix (or, on some util-linux versions, as nothing at
  # all), udev creates no by-label link, and the guest waits there until it
  # drops into an unusable emergency shell.
  # https://github.com/microvm-nix/microvm.nix/issues/605
  checkProbeCommand = lib.optionalString (config.microvm.storeDiskType == "erofs") ''
    echo Checking that the store disk is identified as erofs with LABEL=nix-store
    probe=$(blkid -p -o udev "$out")
    if ! grep -qx 'ID_FS_TYPE=erofs' <<<"$probe" ||
       ! grep -qx 'ID_FS_LABEL=nix-store' <<<"$probe"; then
      cat >&2 <<EOF
ERROR: blkid does not identify the store disk as erofs with LABEL=nix-store.

The guest mounts this disk through /dev/disk/by-label/nix-store, so an
ambiguous probe leaves it without its store and drops it into the emergency
shell, where the locked root account makes the console useless.

libblkid probes short magic values at fixed offsets, and the erofs inode count
(little-endian 64-bit at 0x410) overlaps the MINIX v1/v2 magic at the same
offset, so an unlucky inode count makes the probe report minix instead -- or
nothing at all.

See https://github.com/microvm-nix/microvm.nix/issues/605

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
        nativeBuildInputs = [
          pkgs.buildPackages.time
          pkgs.buildPackages.bubblewrap
          pkgs.buildPackages.util-linux
          {
            squashfs = pkgs.buildPackages.squashfs-tools-ng;
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
