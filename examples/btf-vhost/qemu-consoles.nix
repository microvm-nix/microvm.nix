# examples/btf-vhost/qemu-consoles.nix
#
# QEMU command-line arguments for console setup.
#
# This configures two console types accessible via TCP sockets:
#
# ┌─────────────────────────────────────────────────────────────────┐
# │ ttyS0 (serialPort) - Emulated 16550 UART                        │
# │   • Available very early in boot (before virtio drivers load)   │
# │   • Captures kernel panic messages                              │
# │   • Slower - each byte traps to hypervisor                      │
# │   • Use for: kernel console, debugging, early boot issues       │
# ├─────────────────────────────────────────────────────────────────┤
# │ hvc0 (virtioConsolePort) - virtio-console                       │
# │   • Fast - native virtio, batched I/O                           │
# │   • Lower CPU overhead                                          │
# │   • Supports terminal resize                                    │
# │   • NOT available until virtio drivers load                     │
# │   • Use for: interactive login sessions                         │
# └─────────────────────────────────────────────────────────────────┘

{ config }:

[
  # ──────────────────────────────────────────────────────────────────
  # ttyS0: Traditional serial console via TCP
  # ──────────────────────────────────────────────────────────────────
  # This emulates a 16550 UART serial port. It's slower than virtio
  # but available very early in boot, before virtio drivers load.
  # Essential for seeing early kernel messages and panic output.
  #
  # The kernel console=ttyS0 parameter directs kernel output here.
  # We also run a getty so you can login via this port.
  "-chardev"
  "socket,id=serial0,host=localhost,port=${toString config.serialPort},server=on,wait=off"
  "-serial"
  "chardev:serial0"

  # ──────────────────────────────────────────────────────────────────
  # hvc0: virtio-console via TCP (fast interactive console)
  # ──────────────────────────────────────────────────────────────────
  # virtio-console uses the virtio-serial bus for console access.
  # Much faster than emulated UART - uses batched I/O and has
  # lower CPU overhead. Supports terminal resize.
  #
  # Only available after virtio drivers load, so not useful for
  # early boot debugging, but ideal for interactive sessions.
  #
  # Device topology: virtio-serial-device -> virtconsole -> chardev
  # Note: We use virtio-serial-device (not -pci) because the
  # "microvm" machine type uses MMIO, not PCI.
  "-device"
  "virtio-serial-device"
  "-chardev"
  "socket,id=virtcon0,host=localhost,port=${toString config.virtioConsolePort},server=on,wait=off"
  "-device"
  "virtconsole,chardev=virtcon0"
]
