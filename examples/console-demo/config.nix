# examples/console-demo/config.nix
#
# Shared configuration for the console demo.

{
  # ════════════════════════════════════════════════════════════════════════
  # VM Resources
  # ════════════════════════════════════════════════════════════════════════

  mem = 512; # RAM in MB
  vcpu = 1; # Number of virtual CPUs

  # ════════════════════════════════════════════════════════════════════════
  # TCP Ports for Console Access
  # ════════════════════════════════════════════════════════════════════════
  # These allow connecting to the VM's consoles via netcat while the VM
  # runs in the background.

  # ttyS0 - Traditional 16550 UART serial port
  # Available immediately at boot, before any drivers load.
  # Use for: kernel messages, early boot debugging, panic output.
  serialPort = 4440;

  # hvc0 - virtio-console
  # Fast paravirtualized console, available after virtio drivers load.
  # Use for: interactive sessions, high-throughput I/O.
  virtioConsolePort = 4441;

  # ════════════════════════════════════════════════════════════════════════
  # Test Timeouts and Polling
  # ════════════════════════════════════════════════════════════════════════
  # These control the run-test script behavior.
  # Generous timeouts for reliability on slow or overloaded machines.

  # How often to poll for port availability and boot status (seconds)
  pollInterval = 1;

  # Maximum time to wait for console TCP ports to be available (seconds)
  portTimeout = 120;

  # Maximum time to wait for system to boot and shell to respond (seconds)
  bootTimeout = 180;

  # Timeout for individual netcat commands when testing console (seconds)
  commandTimeout = 5;
}
