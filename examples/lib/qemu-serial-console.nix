# examples/lib/qemu-serial-console.nix
#
# QEMU arguments for TCP-accessible serial console (ttyS0).
# This is the minimal console setup for testing - works without virtio drivers.
#
# The serial console is available immediately at boot, before any drivers load,
# making it ideal for automated testing and early boot debugging.
#
# Usage:
#   let
#     constants = import ../lib/constants.nix;
#     serialConsoleArgs = import ../lib/qemu-serial-console.nix {
#       serialPort = constants.btf-vhost.serialPort;
#     };
#   in
#   {
#     microvm.qemu.extraArgs = serialConsoleArgs ++ otherArgs;
#   }
#
# Connect with:
#   nc localhost <serialPort>

{ serialPort }:

[
  # Create a character device backed by a TCP socket
  # server=on: QEMU listens for connections
  # wait=off: VM starts without waiting for a client to connect
  "-chardev"
  "socket,id=serial0,host=localhost,port=${toString serialPort},server=on,wait=off"

  # Connect the serial port to our chardev
  "-serial"
  "chardev:serial0"
]
