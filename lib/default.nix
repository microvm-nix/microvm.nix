{ lib }:
rec {
  hypervisors = [
    "qemu"
    "cloud-hypervisor"
    "firecracker"
    "crosvm"
    "kvmtool"
    "stratovirt"
    "alioth"
  ];

  hypervisorsWithNetwork = hypervisors;

  defaultFsType = "ext4";

  withDriveLetters = { volumes, hypervisor, storeOnDisk, ... }:
    let
      offset =
        if storeOnDisk
        then 1
        else 0;
    in
    map ({ fst, snd }:
      fst // {
        letter = snd;
      }
    ) (lib.zipLists volumes (
      lib.drop offset lib.strings.lowerChars
    ));

  createVolumesScript = pkgs: volumes:
    lib.optionalString (volumes != []) (
      lib.optionalString (lib.any (v: v.autoCreate) volumes) ''
        PATH=$PATH:${with pkgs.buildPackages; lib.makeBinPath [ coreutils util-linux e2fsprogs xfsprogs dosfstools btrfs-progs ]}
      '' +
      pkgs.lib.concatMapStringsSep "\n" (
        { image
        , label
        , size ? throw "Specify a size for volume ${image} or use autoCreate = false"
        , mkfsExtraArgs
        , fsType ? defaultFsType
        , autoCreate ? true
        , ...
        }: pkgs.lib.warnIf
          (label != null && !autoCreate) "Volume is not automatically labeled unless autoCreate is true. Volume has to be labeled manually, otherwise it will not be identified"
          (let labelOption =
                 if autoCreate then
                   (if builtins.elem fsType ["ext2" "ext3" "ext4" "xfs" "btrfs"] then "-L"
                    else if fsType == "vfat" then "-n"
                    else (pkgs.lib.warnIf (label != null)
                      "Will not label volume ${label} with filesystem type ${fsType}. Open an issue on the microvm.nix project to request a fix."
                      null))
                 else null;
               labelArgument =
                 if (labelOption != null && label != null) then "${labelOption} '${label}'"
                 else "";
               mkfsExtraArgsString =
                 if mkfsExtraArgs != null
                 then lib.escapeShellArgs mkfsExtraArgs
                 else " ";
           in (lib.optionalString autoCreate ''

              if [ ! -e '${image}' ]; then
                touch '${image}'
                # Mark NOCOW
                chattr +C '${image}' || true
                truncate -s ${toString size}M '${image}'
                mkfs.${fsType} ${labelArgument} ${mkfsExtraArgsString} '${image}'
              fi
            ''))
      ) volumes
    );

  buildRunner = import ./runner.nix;

  makeMacvtap = { microvmConfig, hypervisorConfig }:
    import ./macvtap.nix {
      inherit microvmConfig hypervisorConfig lib;
    };

  /*
    extractOptValues - Extract and remove all occurrences of a command-line option and its values from a list of arguments.

    Description:
      This function searches for a specified option flag in a list of command-line arguments,
      extracts ALL associated values, and returns both the values and a filtered list with
      all occurrences of the option flag and its values removed. The order of all other
      arguments is preserved. Uses tail recursion to process the argument list.

    Parameters:
      optFlag :: String | [String] - The option flag(s) to search for. Can be:
                                     - A single string (e.g., "-platform")
                                     - A list of strings (e.g., ["-p" "-platform"])
                                     All matching flags and their values are extracted
      extraArgs :: [String] - A list of command-line arguments

    Returns:
      {
        values :: [String] - List of all values associated with matching flags (empty list if none found)
        args :: [String] - The input list with all matched flags and their values removed
      }

    Examples:
      # Extract single occurrence:
      extractOptValues "-platform" ["-vnc" ":0" "-platform" "linux" "-usb"]
      => { values = ["linux"]; args = ["-vnc" ":0" "-usb"]; }

      # Extract multiple occurrences:
      extractOptValues "-platform" ["-a" "a" "-b" "b" "-c" "c" "-b" "b2"]
      => { values = ["b" "b2"]; args = ["-b" "b" "-c" "c"]; }

      # Extract with multiple flag aliases:
      extractOptValues ["-p" "-platform"] ["-p" "short" "-vnc" ":0" "-platform" "long" "-usb"]
      => { values = ["short" "long"]; args = ["-vnc" ":0" "-usb"]; }

      # Degenerate case with no matches:
      extractOptValues ["-p" "-platform"] ["-vnc" ":0" "-usb"]
      => { values = []; args = ["-vnc" ":0" "-usb"]; }
  */
  extractOptValues = optFlag: extraArgs:
    let
      flags = if builtins.isList optFlag then optFlag else [optFlag];

      processArgs = args: values: acc:
        if args == [] then
          { values = values; args = acc; }
        else if (builtins.elem (builtins.head args) flags) && (builtins.length args) > 1 then
          # Found one of the option flags, skip it and its value
          processArgs (builtins.tail (builtins.tail args)) (values ++ [(builtins.elemAt args 1)]) acc
        else
          # Not the option we're looking for, keep this element
          processArgs (builtins.tail args) values (acc ++ [(builtins.head args)]);
    in
      processArgs extraArgs [] [];
}
