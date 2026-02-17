# examples/lib/cloud-hypervisor-console.nix
#
# cloud-hypervisor arguments for Unix socket console (virtio-console/hvc0).
#
# cloud-hypervisor doesn't support TCP sockets for console, only:
# - tty (terminal)
# - pty (pseudo-terminal)
# - file=<path> (log to file)
# - socket=<path> (Unix domain socket)
#
# We use Unix sockets for automated testing as they can be connected
# via socat and don't require port allocation.
#
# Usage:
#   let
#     chConsole = import ../lib/cloud-hypervisor-console.nix {
#       consolePath = "/tmp/microvm-test/console.sock";
#     };
#   in
#   {
#     # These args are passed via environment or wrapper script
#     # since cloud-hypervisor is invoked by the microvm runner
#   }
#
# Note: The socket path must be passed to the microvm runner somehow.
# Options:
# 1. Environment variable (MICROVM_CONSOLE_SOCKET)
# 2. Wrapper script that modifies cloud-hypervisor args
# 3. microvm.qemu.extraArgs equivalent for cloud-hypervisor

{ consolePath }:

{
  # cloud-hypervisor console arguments
  # --console socket=<path> enables virtio-console on a Unix socket
  consoleArgs = [
    "--console"
    "socket=${consolePath}"
  ];

  # Kernel parameters to direct console output to hvc0
  kernelParams = [
    "console=hvc0"
  ];

  # For serial (ttyS0), cloud-hypervisor uses --serial
  # But socket isn't supported for serial, only for console (virtio)
  # So we use virtio-console (hvc0) for socket-based testing
}
