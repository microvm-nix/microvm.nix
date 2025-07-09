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

  withDriveLetters = { volumes, storeOnDisk, ... }:
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
      extractOptValues "-b" ["-a" "a" "-b" "b" "-c" "c" "-b" "b2"]
      => { values = ["b" "b2"]; args = ["-a" "a" "-c" "c"]; }

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

  /*
    extractParamValue - Extract a parameter value from comma-separated key=value options

    Description:
      Extracts the value of a specified parameter from a comma-separated string
      of key=value pairs (e.g., "key1=val1,key2=val2"). Returns the first match.

    Parameters:
      param :: String - The parameter name to search for
      opts :: String -  The options string

    Returns:
      String | null - The parameter value if found, null otherwise

    Example:
      extractParamValue "socket" "cid=5,socket=notify.vsock" => "notify.vsock"
  */
  extractParamValue = param: opts:
    if opts == "" || opts == null then null
    else let m = builtins.match ".*${param}=([^,]+).*" opts;
         in if m == null then null else builtins.head m;
}
