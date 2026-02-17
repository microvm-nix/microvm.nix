# examples/lib/constants.nix
#
# Centralized port and configuration for all examples.
# This ensures no port conflicts when running tests concurrently.
#
# Port ranges (keeping existing ports for backward compatibility):
#   4321-4339: btf-vhost (existing: 4321, 4322)
#   4440-4459: console-demo (existing: 4440, 4441)
#   4460-4479: graphics
#   4480-4499: microvms-host
#   4500-4519: qemu-vnc
#   4520-4539: http-server
#   4540-4559: valkey-server
#   15900-15910: VNC displays (moved from 5900 to avoid libvirt conflicts)
#   16379: valkey user-mode forwarding
#   28080: http user-mode forwarding
#
# Note: Process naming uses networking.hostName from each example's NixOS config,
# not constants defined here. This avoids duplication.
#
# Usage:
#   let
#     constants = import ../lib/constants.nix;
#     config = constants.btf-vhost;
#   in
#   ...

{
  # btf-vhost (existing example - preserving original ports)
  btf-vhost = {
    # Console ports (preserved from existing config)
    serialPort = 4321; # ttyS0
    virtioConsolePort = 4322; # hvc0

    # Network configuration (example-specific)
    tapInterface = "vm-btf";
    bridgeInterface = "microvm-br0";
    bridgeAddr = "10.90.0.1";
    vmAddr = "10.90.0.2";
    vmMac = "02:00:00:01:02:03";

    # VM resources
    mem = 4096;
    vcpu = 2;

    # Test timeouts (seconds)
    pollInterval = 1;
    portTimeout = 120;
    bootTimeout = 180;
    commandTimeout = 5;
  };

  # console-demo (existing example - preserving original ports)
  console-demo = {
    serialPort = 4440; # ttyS0 (preserved)
    virtioConsolePort = 4441; # hvc0 (preserved)

    mem = 512;
    vcpu = 1;

    pollInterval = 1;
    portTimeout = 120;
    bootTimeout = 180;
    commandTimeout = 5;
  };

  # graphics (cloud-hypervisor)
  # Note: This example uses cloud-hypervisor, not QEMU.
  # VNC is provided by cloud-hypervisor's graphics support.
  # No serial console - uses VNC screenshot testing instead.
  graphics = {
    vncPort = 15901; # VNC display (moved from 5901 to avoid libvirt conflicts)

    mem = 2048;
    vcpu = 2;

    pollInterval = 1;
    portTimeout = 120;
    bootTimeout = 180;
    commandTimeout = 5;
  };

  # microvms-host (new testing support)
  microvms-host = {
    serialPort = 4480;

    mem = 8192;
    vcpu = 4;

    pollInterval = 2; # Longer due to nested VMs
    portTimeout = 180; # Longer startup time
    bootTimeout = 300;
    commandTimeout = 10;
  };

  # qemu-vnc (new testing support)
  qemu-vnc = {
    serialPort = 4500;
    vncPort = 15900; # VNC display (moved from 5900 to avoid libvirt conflicts)

    mem = 2048;
    vcpu = 2;

    pollInterval = 1;
    portTimeout = 120;
    bootTimeout = 180;
    commandTimeout = 5;
  };

  # http-server - Nginx static web server (user-mode networking)
  http-server = {
    # Console ports (TCP sockets for nc access)
    serialPort = 4520; # ttyS0 - early boot, kernel messages
    virtioConsolePort = 4521; # hvc0 - fast interactive console

    # HTTP service
    httpPortUser = 28080; # Host port (user-mode forwarding)
    httpPortGuest = 80; # Guest port (nginx listens here)

    # TAP networking (optional, for production-like setup)
    tapInterface = "vm-http";
    bridgeInterface = "microvm-br0";
    bridgeAddr = "10.90.0.1"; # Shared with btf-vhost
    vmAddr = "10.90.0.10";
    vmMac = "02:00:00:00:00:10";

    # VM resources
    mem = 512;
    vcpu = 1;

    # Test timeouts (seconds)
    pollInterval = 1;
    portTimeout = 60;
    bootTimeout = 120;
    commandTimeout = 5;
  };

  # valkey-server - In-memory cache/database (user-mode networking)
  valkey-server = {
    # Console ports
    serialPort = 4540;
    virtioConsolePort = 4541;

    # Valkey service
    valkeyPortUser = 16379; # Host port (user-mode forwarding)
    valkeyPortGuest = 6379; # Guest port (Valkey listens here)

    # TAP networking (optional)
    tapInterface = "vm-valkey";
    bridgeInterface = "microvm-br0";
    bridgeAddr = "10.90.0.1";
    vmAddr = "10.90.0.11";
    vmMac = "02:00:00:00:00:11";

    # VM resources
    mem = 512;
    vcpu = 1;

    # Test timeouts (shorter - Valkey starts very fast)
    pollInterval = 1;
    portTimeout = 30;
    bootTimeout = 60;
    commandTimeout = 5;
  };
}
