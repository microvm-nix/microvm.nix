{ pkgs
, microvmConfig
, toplevel
}:

let
  inherit (pkgs) lib;

  inherit (microvmConfig) fqdnOrHostName vmHostPackages;

  inherit (import ./. { inherit lib; }) makeMacvtap withDriveLetters extractOptValues extractParamValue;
  inherit (import ./volumes.nix { pkgs = microvmConfig.vmHostPackages; }) createVolumesScript;
  inherit (makeMacvtap {
    inherit microvmConfig hypervisorConfig;
  }) openMacvtapFds macvtapFds;

  hypervisorConfig = import (./runners + "/${microvmConfig.hypervisor}.nix") {
    inherit pkgs microvmConfig macvtapFds withDriveLetters extractOptValues extractParamValue;
  };

  inherit (hypervisorConfig) command canShutdown shutdownCommand;
  supportsNotifySocket = hypervisorConfig.supportsNotifySocket or false;
  preStart = hypervisorConfig.preStart or microvmConfig.preStart;
  tapMultiQueue = hypervisorConfig.tapMultiQueue or false;
  setBalloonScript = hypervisorConfig.setBalloonScript or null;

  execArg = lib.optionalString microvmConfig.prettyProcnames
    ''-a "microvm@${fqdnOrHostName}"'';


  binScripts = microvmConfig.binScripts // {
    microvm-run = ''
      set -eou pipefail
      ${preStart}
      ${createVolumesScript microvmConfig.volumes}
      ${lib.optionalString (hypervisorConfig.requiresMacvtapAsFds or false) openMacvtapFds}
      runtime_args=${lib.optionalString (microvmConfig.extraArgsScript != null) ''
        $(${microvmConfig.extraArgsScript})
      ''}

      exec ${execArg} ${command} ''${runtime_args:-}
    '';
  } // lib.optionalAttrs canShutdown {
    microvm-shutdown = shutdownCommand;
  } // lib.optionalAttrs (setBalloonScript != null) {
    microvm-balloon = ''
      set -e

      if [ -z "$1" ]; then
        echo "Usage: $0 <balloon-size-mb>"
        exit 1
      fi

      SIZE=$1
      ${setBalloonScript}
    '';
  };

  binScriptPkgs = lib.mapAttrs (scriptName: lines:
    vmHostPackages.writeShellScript "microvm-${fqdnOrHostName}-${scriptName}" lines
  ) binScripts;
in

vmHostPackages.buildPackages.runCommand "microvm-${microvmConfig.hypervisor}-${fqdnOrHostName}"
{
  # for `nix run`
  meta.mainProgram = "microvm-run";
  passthru = {
    inherit canShutdown supportsNotifySocket tapMultiQueue;
    inherit (microvmConfig) hypervisor;
  };
} ''
  mkdir -p $out/bin

  ${lib.concatMapStrings (scriptName: ''
    ln -s ${binScriptPkgs.${scriptName}} $out/bin/${scriptName}
  '') (builtins.attrNames binScriptPkgs)}

  mkdir -p $out/share/microvm
  ${lib.optionalString microvmConfig.systemSymlink ''
  ln -s ${toplevel} $out/share/microvm/system
  ''}

  echo vnet_hdr > $out/share/microvm/tap-flags
  ${lib.optionalString tapMultiQueue ''
    echo multi_queue >> $out/share/microvm/tap-flags
  ''}
  ${lib.concatMapStringsSep " " (interface:
    lib.optionalString (interface.type == "tap" && interface ? id) ''
      echo "${interface.id}" >> $out/share/microvm/tap-interfaces
    '') microvmConfig.interfaces}

  ${lib.concatMapStringsSep " " (interface:
    lib.optionalString (
      interface.type == "macvtap" &&
      interface ? id &&
      (interface.macvtap.link or null) != null &&
      (interface.macvtap.mode or null) != null
    ) ''
      echo "${builtins.concatStringsSep " " [
        interface.id
        interface.mac
        interface.macvtap.link
        (builtins.toString interface.macvtap.mode)
      ]}" >> $out/share/microvm/macvtap-interfaces
    '') microvmConfig.interfaces}


  ${lib.concatMapStrings ({ tag, socket, source, proto, ... }:
      lib.optionalString (proto == "virtiofs") ''
        mkdir -p $out/share/microvm/virtiofs/${tag}
        echo "${socket}" > $out/share/microvm/virtiofs/${tag}/socket
        echo "${source}" > $out/share/microvm/virtiofs/${tag}/source
      ''
    ) microvmConfig.shares}

  ${lib.concatMapStrings ({ bus, path, ... }: ''
    echo "${path}" >> $out/share/microvm/${bus}-devices
  '') microvmConfig.devices}
''
