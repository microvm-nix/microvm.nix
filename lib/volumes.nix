{ pkgs }:
let
  inherit (pkgs) lib;

  inherit
    (import ../../lib {
      inherit lib;
    })
    defaultFsType
    ;

  fsTypeToUtil =
    fs:
    with pkgs;
    {
      "ext2" = e2fsprogs;
      "ext3" = e2fsprogs;
      "ext4" = e2fsprogs;
      "xfs" = xfsprogs;
      "btrfs" = btrfs-progs;
      "vfat" = dosfstools;
    }
    .${fs} or (throw "Do not know how to handle ${fs}");
  collectFsTypes = volumes: map (v: v.fsType) volumes;
  collectFsUtils = volumes: map (fsType: fsTypeToUtil fsType) (collectFsTypes volumes);

in
{
  createVolumesScript =
    volumes:
    lib.optionalString (volumes != [ ]) (
      lib.optionalString (lib.any (v: v.autoCreate) volumes) ''
        PATH=$PATH:${lib.makeBinPath ([ pkgs.coreutils ] ++ (collectFsUtils volumes))}
      ''
      + lib.concatMapStringsSep "\n" (
        {
          image,
          label,
          size ? throw "Specify a size for volume ${image} or use autoCreate = false",
          mkfsExtraArgs,
          fsType ? defaultFsType,
          autoCreate ? true,
          ...
        }:
        lib.warnIf (label != null && !autoCreate)
          "Volume is not automatically labeled unless autoCreate is true. Volume has to be labeled manually, otherwise it will not be identified"
          (
            let
              labelOption =
                if autoCreate then
                  (
                    if
                      builtins.elem fsType [
                        "ext2"
                        "ext3"
                        "ext4"
                        "xfs"
                        "btrfs"
                      ]
                    then
                      "-L"
                    else if fsType == "vfat" then
                      "-n"
                    else
                      lib.warnIf (label != null)
                        "Will not label volume ${label} with filesystem type ${fsType}. Open an issue on the microvm.nix project to request a fix."
                        null

                  )
                else
                  null;
              labelArgument = lib.optionalString (
                labelOption != null && label != null
              ) "${labelOption} '${label}'";
              mkfsExtraArgsString = if mkfsExtraArgs != null then lib.escapeShellArgs mkfsExtraArgs else " ";
            in
            lib.optionalString autoCreate ''
              if [ ! -e '${image}' ]; then
                touch '${image}'
                # Mark NOCOW
                chattr +C '${image}' || true
                truncate -s ${toString size}M '${image}'
                mkfs.${fsType} ${labelArgument} ${mkfsExtraArgsString} '${image}'
              fi
            ''
          )
      ) volumes
    );
}
