{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.vsock;
in
{
  options.microvm.vsock.ssh = {
    enable = lib.mkEnableOption ''
      SSH server listening on VSOCK for host-to-guest connections.

      When enabled, the guest's SSH server will listen on the VSOCK interface, allowing the host to connect without
      network configuration. Requires `microvm.vsock.cid` to be set.

      From the host, connect using:
      - For qemu/crosvm/kvmtool: `ssh vsock/<CID>`
      - For cloud-hypervisor: `ssh vsock-mux/<path-to-notify.vsock>`
      - Or use: `microvm -s <vmname>`
    '';
  };

  config = lib.mkIf cfg.ssh.enable {
    assertions = [{
      assertion = cfg.cid != null;
      message = "microvm.vsock.ssh.enable requires microvm.vsock.cid to be set";
    }];

    services.openssh.enable = true;

    # systemd's ssh-generator automatically creates sshd-vsock.socket when it detects VSOCK is available,
    # so we don't need to configure the socket manually. It will listen on vsock::22.
  };
}
