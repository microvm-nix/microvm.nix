# examples/console-demo/qemu-consoles.nix
#
# QEMU command-line arguments for TCP-accessible consoles.
#
# This configures two distinct console types:
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │ ttyS0 (serial) - Emulated 16550 UART                                │
# │                                                                     │
# │   How it works:                                                     │
# │   - QEMU emulates a traditional PC serial port (COM1)               │
# │   - Each character write traps from guest to hypervisor             │
# │   - Available immediately - no drivers needed                       │
# │                                                                     │
# │   Characteristics:                                                  │
# │   - Slow: emulation overhead per byte                               │
# │   - Universal: works at any boot stage                              │
# │   - Reliable: captures kernel panics before virtio loads            │
# │                                                                     │
# │   Use for: kernel console, early boot, crash debugging              │
# ├─────────────────────────────────────────────────────────────────────┤
# │ hvc0 (virtio-console) - Paravirtualized console                     │
# │                                                                     │
# │   How it works:                                                     │
# │   - Built on virtio-serial transport                                │
# │   - Guest driver batches writes into virtqueue buffers              │
# │   - Host processes buffers efficiently (fewer VM exits)             │
# │                                                                     │
# │   Characteristics:                                                  │
# │   - Fast: batched I/O, minimal hypervisor traps                     │
# │   - Delayed: requires virtio-console driver to load first           │
# │   - Feature-rich: supports terminal resize (SIGWINCH)               │
# │                                                                     │
# │   Use for: interactive login, high-throughput logging               │
# └─────────────────────────────────────────────────────────────────────┘

{ config }:

[
  # ──────────────────────────────────────────────────────────────────────
  # ttyS0: Serial console on TCP socket
  # ──────────────────────────────────────────────────────────────────────
  # Creates a character device backed by a TCP socket.
  # server=on: QEMU listens for connections
  # wait=off: VM starts without waiting for a client to connect
  "-chardev"
  "socket,id=serial0,host=localhost,port=${toString config.serialPort},server=on,wait=off"
  "-serial"
  "chardev:serial0"

  # ──────────────────────────────────────────────────────────────────────
  # hvc0: virtio-console on TCP socket
  # ──────────────────────────────────────────────────────────────────────
  # virtio-console requires the virtio-serial bus as transport.
  # We use virtio-serial-device (not -pci) because the microvm machine
  # type uses MMIO for device discovery, not PCI.
  #
  # Device hierarchy:
  #   virtio-serial-device (transport bus)
  #     └── virtconsole (console device)
  #           └── chardev:virtcon0 (backend: TCP socket)
  "-device"
  "virtio-serial-device"
  "-chardev"
  "socket,id=virtcon0,host=localhost,port=${toString config.virtioConsolePort},server=on,wait=off"
  "-device"
  "virtconsole,chardev=virtcon0"
]
