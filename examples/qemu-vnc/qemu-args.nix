# examples/qemu-vnc/qemu-args.nix
#
# QEMU command-line arguments for VNC and input devices.

[
  # VNC server on display :0 (port 5900)
  "-vnc"
  ":0"

  # QXL graphics adapter (optimized for virtualization)
  "-vga"
  "qxl"

  # Input devices for VNC interaction
  "-device"
  "virtio-keyboard"
  "-usb"
  "-device"
  "usb-tablet,bus=usb-bus.0" # Absolute positioning for mouse
]
