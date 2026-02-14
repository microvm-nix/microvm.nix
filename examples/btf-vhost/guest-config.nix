# examples/btf-vhost/guest-config.nix
#
# NixOS configuration for the guest VM.
# This includes networking, SSH, console gettys, packages, and motd.

{
  lib,
  pkgs,
  config,
}:

{
  # ════════════════════════════════════════════════════════════════════
  # Kernel Console Configuration
  # ════════════════════════════════════════════════════════════════════
  # We configure BOTH consoles in the kernel command line:
  # - console=ttyS0: Early boot messages go to serial (available immediately)
  # - console=hvc0: Later messages also go to virtio-console
  #
  # The LAST console= parameter becomes /dev/console (used by systemd, etc.)
  # So hvc0 will be the primary console once virtio loads, but we still
  # capture early boot on ttyS0.
  boot.kernelParams = [
    "console=ttyS0,115200" # Serial: early boot, kernel panics
    "console=hvc0" # virtio-console: primary after boot
  ];

  # ════════════════════════════════════════════════════════════════════
  # Getty Services (Login Prompts)
  # ════════════════════════════════════════════════════════════════════
  # Run login prompts on both consoles so you can login via either

  # ttyS0: Serial console getty (slower, but always available)
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # hvc0: virtio-console getty (fast, for interactive use)
  systemd.services."serial-getty@hvc0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # Autologin on consoles for convenience
  services.getty.autologinUser = "root";

  # ════════════════════════════════════════════════════════════════════
  # Network Configuration
  # ════════════════════════════════════════════════════════════════════
  # Use systemd-networkd with static IP addressing.
  systemd.network = {
    enable = true;
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      addresses = [ { Address = "${config.vmAddr}/24"; } ];
      routes = [ { Gateway = config.bridgeAddr; } ];
      dns = [
        "8.8.8.8"
        "8.8.4.4"
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [
    22
    5001
  ]; # SSH + iperf2

  # ════════════════════════════════════════════════════════════════════
  # SSH Configuration (INSECURE - for testing only)
  # ════════════════════════════════════════════════════════════════════
  # WARNING: This allows root login with empty password!
  # This is intentional for ease of testing. Do not use in production.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };

  # Set empty root password for passwordless SSH
  users.users.root = {
    password = ""; # Empty password
    openssh.authorizedKeys.keys = [
      # Optionally add your public key here for key-based auth
    ];
  };

  # Disable password quality checks (allow empty password)
  security.pam.services.sshd.allowNullPassword = true;

  # ════════════════════════════════════════════════════════════════════
  # eBPF/BTF Tools
  # ════════════════════════════════════════════════════════════════════
  # These tools demonstrate BTF is working in the kernel.
  environment.systemPackages = with pkgs; [
    bcc # BPF Compiler Collection (tcptop, execsnoop, etc.)
    bpftrace # High-level tracing language for eBPF
    iproute2 # For ss, ip commands
    iperf2 # For testing network throughput
  ];

  # ════════════════════════════════════════════════════════════════════
  # Message of the Day
  # ════════════════════════════════════════════════════════════════════
  users.motd = ''
    ╔═══════════════════════════════════════════════════════════════╗
    ║              BTF + vhost MicroVM Test Environment             ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Test BTF/eBPF (requires root):                                ║
    ║   tcptop              # Show TCP send/recv by host            ║
    ║   execsnoop           # Trace new processes                   ║
    ║   bpftrace -e 'tracepoint:syscalls:sys_enter_* { ... }'       ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Test vhost networking throughput:                             ║
    ║   Host:  iperf -s                                             ║
    ║   VM:    iperf -c ${config.bridgeAddr}                              ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Network info:                                                 ║
    ║   VM IP: ${config.vmAddr}    Gateway: ${config.bridgeAddr}          ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ ⚠  WARNING: SSH allows root with empty password (testing)     ║
    ╚═══════════════════════════════════════════════════════════════╝
  '';
}
