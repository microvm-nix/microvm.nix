# microvm.instance.enable: a runner shared by several MicroVMs. Each
# instance's values live in instance/ of its state directory, which is the
# working directory of the host's microvm@ and microvm-tap-interfaces@ units.
{ config, lib, pkgs, ... }:

let
  ip = lib.getExe' pkgs.iproute2 "ip";

  # TODO: don't hardcode but obtain from host config
  user = "microvm";
in
lib.mkIf config.microvm.instance.enable {
  # A machine-id derived from the hostname would be the same for every
  # instance. Instances can pass their own as the system.machine_id credential.
  microvm.machineId = lib.mkDefault null;

  # /etc/hostname would take precedence over the system.hostname credential.
  environment.etc.hostname.enable = lib.mkDefault false;

  microvm.binScripts = {
    tap-up = ''
      set -eou pipefail
      [ -f instance/interfaces ] || exit 0
      # multi-queue like the runner's tap netdevs when there is more than one vCPU
      flags=vnet_hdr
      vcpu=${toString config.microvm.vcpu}
      [ ! -f instance/vcpu ] || vcpu=$(< instance/vcpu)
      [ "$vcpu" = 1 ] || flags="$flags multi_queue"
      while read -r id _; do
        [ -n "$id" ] || continue
        if ! [[ "$id" =~ ^[A-Za-z0-9_.-]{1,15}$ ]]; then
          echo "invalid instance/interfaces: '$id' is not an interface name of up to 15 characters" >&2
          exit 1
        fi
        if [ -e "/sys/class/net/$id" ]; then
          ${ip} link delete "$id"
        fi
        # shellcheck disable=SC2086
        ${ip} tuntap add name "$id" mode tap user '${user}' $flags
        ${ip} link set "$id" up
      done < instance/interfaces
    '';

    tap-down = ''
      set -ou pipefail
      [ -f instance/interfaces ] || exit 0
      while read -r id _; do
        [ -n "$id" ] || continue
        ${ip} link delete "$id"
      done < instance/interfaces
    '';
  };
}
