# examples/http-server/qemu-consoles.nix
#
# QEMU arguments for dual console setup (serial + virtio).
#
# Console architecture:
#   ttyS0 (serial)  - Available at boot, slow, captures panics
#   hvc0 (virtio)   - Available after driver load, fast, interactive

{ config }:

[
  # ──────────────────────────────────────────────────────────────────────
  # Serial console (ttyS0) on TCP socket
  # ──────────────────────────────────────────────────────────────────────
  "-chardev"
  "socket,id=serial0,host=localhost,port=${toString config.serialPort},server=on,wait=off"
  "-serial"
  "chardev:serial0"

  # ──────────────────────────────────────────────────────────────────────
  # Virtio console (hvc0) on TCP socket
  # ──────────────────────────────────────────────────────────────────────
  "-device"
  "virtio-serial-device"
  "-chardev"
  "socket,id=virtcon0,host=localhost,port=${toString config.virtioConsolePort},server=on,wait=off"
  "-device"
  "virtconsole,chardev=virtcon0"
]
