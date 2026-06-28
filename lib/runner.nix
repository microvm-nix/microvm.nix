{ pkgs
, microvmConfig
, toplevel
}:

let
  inherit (pkgs) lib;

  inherit (microvmConfig) hostName vmHostPackages;

  inherit (import ./. { inherit lib; }) makeMacvtap withDriveLetters extractOptValues extractParamValue;
  inherit (import ./volumes.nix { pkgs = microvmConfig.vmHostPackages; }) createVolumesScript;
  inherit (makeMacvtap {
    inherit microvmConfig hypervisorConfig;
  }) openMacvtapFds macvtapFds;

  linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;

  hypervisorConfig = import (./runners + "/${microvmConfig.hypervisor}.nix") {
    inherit pkgs microvmConfig macvtapFds withDriveLetters extractOptValues extractParamValue linuxTarget;
  };

  inherit (hypervisorConfig) command canShutdown shutdownCommand;
  supportsNotifySocket = hypervisorConfig.supportsNotifySocket or false;
  preStart = hypervisorConfig.preStart or microvmConfig.preStart;
  tapMultiQueue = hypervisorConfig.tapMultiQueue or false;
  setBalloonScript = hypervisorConfig.setBalloonScript or null;

  execArg = lib.optionalString microvmConfig.prettyProcnames ''-a "microvm@${hostName}"'';

  # TAP interface names for machined registration
  tapInterfaces = lib.filter (i: i.type == "tap" && i ? id) microvmConfig.interfaces;
  tapInterfaceNames = map (i: i.id) tapInterfaces;

  # Generate machine UUID at eval time for consistency across SMBIOS and machined
  # Uses provided machineId or generates UUIDv5 from hostname
  machineUuid =
    if microvmConfig.machineId != null then
      microvmConfig.machineId
    else
      builtins.readFile (
        vmHostPackages.runCommand "machine-uuid" { } ''
          ${vmHostPackages.python3}/bin/python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, "${hostName}"), end="")' > $out
        ''
      );

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
      "$MACHINE_NAME" 2>/dev/null || true
  '';

  # Script to register with systemd-machined
  # Note: NSS hostname resolution (ssh $vmname) doesn't work for VMs, only containers.
  # machined's GetAddresses method requires container namespaces to enumerate IPs.
  registerMachineScript = ''
    set -euo pipefail

    LEADER_PID="''${1:-$$}"
    MACHINE_NAME="${hostName}"
    UUID="${machineUuid}"

    # Convert UUID to decimal bytes for busctl array arguments
    UUID_BYTES=$(echo "$UUID" | tr -d '-' | ${vmHostPackages.gnused}/bin/sed 's/../0x& /g' | ${vmHostPackages.gawk}/bin/awk '{for(i=1;i<=NF;i++) printf "%d ", strtonum($i)}')
    read -r -a UUID_BYTE_ARRAY <<< "$UUID_BYTES"

    IFINDEX_ARRAY=()
    ${lib.concatMapStrings (name: ''
      if [ -e /sys/class/net/${name}/ifindex ]; then
        IFINDEX_ARRAY+=("$(cat /sys/class/net/${name}/ifindex)")
      fi
    '') tapInterfaceNames}
    NUM_IFS=''${#IFINDEX_ARRAY[@]}

    ${lib.optionalString
      (microvmConfig.vsock.cid != null && microvmConfig.hypervisor != "cloud-hypervisor")
      ''
        VSOCK_CID=${toString microvmConfig.vsock.cid}
        SSH_ADDRESS="vsock/${toString microvmConfig.vsock.cid}"
      ''
    }

    MANAGER_INTROSPECT=$(${vmHostPackages.systemd}/bin/busctl introspect \
      org.freedesktop.machine1 \
      /org/freedesktop/machine1 \
      org.freedesktop.machine1.Manager 2>/dev/null || true)

    if [[ "$MANAGER_INTROSPECT" == *"RegisterMachineEx"* ]]; then
      # systemd 259+: use extensible registration for VSOCK/SSH metadata
      EX_PROP_COUNT=5
      EX_ARGS=(
        "$MACHINE_NAME"
        "$EX_PROP_COUNT"
        "Id" "ay" ''${#UUID_BYTE_ARRAY[@]} "''${UUID_BYTE_ARRAY[@]}"
        "Service" "s" "microvm.nix"
        "Class" "s" "vm"
        "LeaderPIDFD" "h" "PIDFD"
        "RootDirectory" "s" "/"
      )

      if [ -n "''${VSOCK_CID:-}" ]; then
        EX_PROP_COUNT=$((EX_PROP_COUNT + 1))
        EX_ARGS+=("VSockCID" "u" "$VSOCK_CID")
      fi

      if [ -n "''${SSH_ADDRESS:-}" ]; then
        EX_PROP_COUNT=$((EX_PROP_COUNT + 1))
        EX_ARGS+=("SSHAddress" "s" "$SSH_ADDRESS")
      fi

      if [ "$NUM_IFS" -gt 0 ]; then
        EX_PROP_COUNT=$((EX_PROP_COUNT + 1))
        EX_ARGS+=("NetworkInterfaces" "ai" "$NUM_IFS" "''${IFINDEX_ARRAY[@]}")
      fi

      EX_ARGS[1]="$EX_PROP_COUNT"

      # This is our very poor mans method to get around upstream pid recycling safety features :)
      ${lib.getExe vmHostPackages.python3} - \
        ${vmHostPackages.systemd}/bin/busctl call \
        org.freedesktop.machine1 \
        /org/freedesktop/machine1 \
        org.freedesktop.machine1.Manager \
        RegisterMachineEx "sa(sv)" \
        "''${EX_ARGS[@]}" \
        <<EOF
    import os; import subprocess; import sys
    try:
      pidfd = os.pidfd_open($LEADER_PID, 0)
    except AttributeError:
      print("Error: Which NixOS version are you running that pidfd_open syscall is not available?!")
      exit(1)
    subprocess.run([str(pidfd) if x == 'PIDFD' else x for x in sys.argv[1:]], pass_fds=[pidfd])
    EOF
    elif [ "$NUM_IFS" -gt 0 ]; then
      ${vmHostPackages.systemd}/bin/busctl call \
        org.freedesktop.machine1 \
        /org/freedesktop/machine1 \
        org.freedesktop.machine1.Manager \
        RegisterMachineWithNetwork "sayssusai" \
        "$MACHINE_NAME" \
        ''${#UUID_BYTE_ARRAY[@]} "''${UUID_BYTE_ARRAY[@]}" \
        "microvm.nix" \
        "vm" \
        "$LEADER_PID" \
        "/" \
        "$NUM_IFS" "''${IFINDEX_ARRAY[@]}"
    else
      ${vmHostPackages.systemd}/bin/busctl call \
        org.freedesktop.machine1 \
        /org/freedesktop/machine1 \
        org.freedesktop.machine1.Manager \
        RegisterMachine "sayssus" \
        "$MACHINE_NAME" \
        ''${#UUID_BYTE_ARRAY[@]} "''${UUID_BYTE_ARRAY[@]}" \
        "microvm.nix" \
        "vm" \
        "$LEADER_PID" \
        "/"
    fi
  '';

  binScripts =
    microvmConfig.binScripts
    // {
      microvm-run = ''
        set -eou pipefail
        ${preStart}
        ${createVolumesScript microvmConfig.volumes}
        ${lib.optionalString (hypervisorConfig.requiresMacvtapAsFds or false) openMacvtapFds}
        runtime_args=${
          lib.optionalString (microvmConfig.extraArgsScript != null) ''
            $(${microvmConfig.extraArgsScript})
          ''
        }

        exec ${execArg} ${command} ''${runtime_args:-}
      '';
    }
    // lib.optionalAttrs canShutdown {
      microvm-shutdown = shutdownCommand;
    }
    // lib.optionalAttrs (setBalloonScript != null) {
      microvm-balloon = ''
        set -e

        if [ -z "$1" ]; then
          echo "Usage: $0 <balloon-size-mb>"
          exit 1
        fi

        SIZE=$1
        ${setBalloonScript}
      '';
    }
    // lib.optionalAttrs microvmConfig.registerWithMachined {
      microvm-register = registerMachineScript;
      microvm-unregister = unregisterMachineScript;
    };

  binScriptPkgs = lib.mapAttrs (
    scriptName: lines: vmHostPackages.writeShellScript "microvm-${hostName}-${scriptName}" lines
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
