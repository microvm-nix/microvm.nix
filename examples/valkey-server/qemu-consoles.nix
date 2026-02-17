# examples/valkey-server/qemu-consoles.nix
#
# QEMU arguments for dual console setup.
# Identical structure to http-server.

{ config }:

[
  # Serial console (ttyS0)
  "-chardev"
  "socket,id=serial0,host=localhost,port=${toString config.serialPort},server=on,wait=off"
  "-serial"
  "chardev:serial0"

  # Virtio console (hvc0)
  "-device"
  "virtio-serial-device"
  "-chardev"
  "socket,id=virtcon0,host=localhost,port=${toString config.virtioConsolePort},server=on,wait=off"
  "-device"
  "virtconsole,chardev=virtcon0"
]
