# examples/btf-vhost/config.nix
#
# Shared configuration variables for the BTF + vhost MicroVM example.
# Edit these values to customize the network and console setup.

{
  # ════════════════════════════════════════════════════════════════════
  # Network Configuration
  # ════════════════════════════════════════════════════════════════════

  # TAP interface name (created on host, used by QEMU)
  tapInterface = "vm-btf";

  # Bridge interface name (created on host for routing)
  bridgeInterface = "microvm-br0";

  # Host-side bridge IP address (gateway for the VM)
  bridgeAddr = "10.90.0.1";

  # VM's static IP address
  vmAddr = "10.90.0.2";

  # VM's MAC address
  vmMac = "02:00:00:01:02:03";

  # ════════════════════════════════════════════════════════════════════
  # Console TCP Ports
  # ════════════════════════════════════════════════════════════════════
  # These ports allow connecting to the VM's consoles via TCP,
  # enabling the VM to run in the background while still accessible.

  # ttyS0 - Traditional serial console (emulated 16550 UART)
  # Use for: early boot messages, kernel panics, debugging
  # Connect with: nc localhost 4321
  serialPort = 4321;

  # hvc0 - virtio-console (fast, batched I/O)
  # Use for: interactive sessions (faster than serial)
  # Connect with: nc localhost 4322
  virtioConsolePort = 4322;

  # ════════════════════════════════════════════════════════════════════
  # VM Resources
  # ════════════════════════════════════════════════════════════════════

  mem = 4096; # RAM in MB
  vcpu = 2; # Number of virtual CPUs
}
