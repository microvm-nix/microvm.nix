{ pkgs
, microvmConfig
, toplevel
}:

let
  inherit (pkgs) lib;

  inherit (microvmConfig) hostName machineId vmHostPackages;

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
    ''-a "microvm@${hostName}"'';


  # TAP interface names for machined registration
  tapInterfaces = lib.filter (i: i.type == "tap" && i ? id) microvmConfig.interfaces;
  tapInterfaceNames = map (i: i.id) tapInterfaces;

  # Script to unregister from systemd-machined
  unregisterMachineScript = ''
    set -euo pipefail
    MACHINE_NAME="${hostName}"

    # Terminate the machine registration (ignore errors if already gone)
    ${vmHostPackages.systemd}/bin/busctl call \
      org.freedesktop.machine1 \
      /org/freedesktop/machine1 \
      org.freedesktop.machine1.Manager \
      TerminateMachine "s" \
      "$MACHINE_NAME" 2>/dev/null
  '';

  # Script to register with systemd-machined
  # Note: NSS hostname resolution (ssh $vmname) doesn't work for VMs, only containers.
  # machined's GetAddresses method requires container namespaces to enumerate IPs.
  # Future: systemd 259+ adds RegisterMachineEx which supports SSHAddress property
  # for VMs, enabling `machinectl ssh` and potentially NSS resolution.
  registerMachineScript = ''
    set -euo pipefail

    LEADER_PID="''${1:-$$}"
    MACHINE_NAME="${hostName}"
    UUID="${machineId}"
    PATH=${lib.makeBinPath (with vmHostPackages; [ coreutils gnused gawk systemd ])}

    # Convert UUID to space-separated decimal bytes for busctl
    UUID_BYTES=$(echo "$UUID" | tr -d '-' | sed 's/../0x& /g' | awk '{for(i=1;i<=NF;i++) printf "%d ", strtonum(''$i)}')

    '' + (if tapInterfaceNames == [] then ''
    # No TAP interfaces, use simple RegisterMachine
    busctl call org.freedesktop.machine1 /org/freedesktop/machine1 \
      org.freedesktop.machine1.Manager RegisterMachine "sayssus" \
      "$MACHINE_NAME" 16 $UUID_BYTES "microvm.nix" "vm" $LEADER_PID "/"
    '' else ''
    # Build network interface index array for RegisterMachineWithNetwork
    IFINDICES=""
    '' + lib.concatMapStrings (name: ''
    if [ -e /sys/class/net/${name}/ifindex ]; then
      IFINDICES="$IFINDICES $(cat /sys/class/net/${name}/ifindex)"
    fi
    '') tapInterfaceNames + ''

    # Count interfaces
    NUM_IFS=$(echo $IFINDICES | wc -w)

    if [ "$NUM_IFS" -gt 0 ]; then
      # Use RegisterMachineWithNetwork with TAP interfaces
      busctl call org.freedesktop.machine1 /org/freedesktop/machine1 \
        org.freedesktop.machine1.Manager RegisterMachineWithNetwork "sayssusai" \
        "$MACHINE_NAME" 16 $UUID_BYTES "microvm.nix" "vm" $LEADER_PID "/" $NUM_IFS $IFINDICES
    else
      # Fallback to simple RegisterMachine
      busctl call org.freedesktop.machine1 /org/freedesktop/machine1 \
        org.freedesktop.machine1.Manager RegisterMachine "sayssus" \
        "$MACHINE_NAME" 16 $UUID_BYTES "microvm.nix" "vm" $LEADER_PID "/"
    fi
    '');

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
  } // lib.optionalAttrs microvmConfig.registerWithMachined {
    microvm-register = registerMachineScript;
    microvm-unregister = unregisterMachineScript;
  };

  binScriptPkgs = lib.mapAttrs (scriptName: lines:
    vmHostPackages.writeShellScript "microvm-${hostName}-${scriptName}" lines
  ) binScripts;
in

vmHostPackages.buildPackages.runCommand "microvm-${microvmConfig.hypervisor}-${hostName}"
{
  # for `nix run`
  meta.mainProgram = "microvm-run";
  passthru = {
    inherit canShutdown supportsNotifySocket tapMultiQueue;
    inherit (microvmConfig) hypervisor registerWithMachined machineId;
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

  # VSOCK info for ssh access
  ${lib.optionalString (microvmConfig.vsock.cid != null) ''
    echo "${toString microvmConfig.vsock.cid}" > $out/share/microvm/vsock-cid
  ''}
  echo "${microvmConfig.hypervisor}" > $out/share/microvm/hypervisor
''
