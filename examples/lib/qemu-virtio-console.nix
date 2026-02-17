# examples/lib/qemu-virtio-console.nix
#
# QEMU arguments for TCP-accessible virtio-console (hvc0).
# Uses virtio-serial for fast, paravirtualized console access.
#
# This is the preferred console for testing with virtio drivers:
#   - Fast: batched I/O via virtqueue, minimal hypervisor traps
#   - Lower CPU overhead than emulated UART (ttyS0)
#   - Supports terminal resize
#
# Note: Requires virtio drivers to be loaded, so not available
# during very early boot. For early boot debugging, use ttyS0.
#
# Usage:
#   let
#     constants = import ../lib/constants.nix;
#     virtioConsoleArgs = import ../lib/qemu-virtio-console.nix {
#       consolePort = constants.btf-vhost.virtioConsolePort;
#     };
#   in
#   {
#     microvm.qemu.extraArgs = virtioConsoleArgs ++ otherArgs;
#   }
#
# Connect with:
#   nc localhost <consolePort>

{ consolePort }:

[
  # ──────────────────────────────────────────────────────────────────────
  # virtio-serial bus
  # ──────────────────────────────────────────────────────────────────────
  # virtio-console requires the virtio-serial bus as transport.
  # We use virtio-serial-device (not -pci) because the microvm machine
  # type uses MMIO for device discovery, not PCI.
  "-device"
  "virtio-serial-device"

  # ──────────────────────────────────────────────────────────────────────
  # TCP socket backend
  # ──────────────────────────────────────────────────────────────────────
  # server=on: QEMU listens for connections
  # wait=off: VM starts without waiting for a client to connect
  "-chardev"
  "socket,id=virtcon0,host=localhost,port=${toString consolePort},server=on,wait=off"

  # ──────────────────────────────────────────────────────────────────────
  # virtio console device
  # ──────────────────────────────────────────────────────────────────────
  # Connect the virtconsole to our chardev backend
  "-device"
  "virtconsole,chardev=virtcon0"
]
