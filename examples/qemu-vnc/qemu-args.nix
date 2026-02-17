# examples/qemu-vnc/qemu-args.nix
#
# QEMU command-line arguments for VNC, input devices, and serial console.
#
# This file is parameterized to accept config for the serial port.

{ config }:

[
  # Serial Console (for automated testing)
  # TCP-accessible serial console on ttyS0
  # Connect with: nc localhost <serialPort>
  "-chardev"
  "socket,id=serial0,host=localhost,port=${toString config.serialPort},server=on,wait=off"
  "-serial"
  "chardev:serial0"

  # VNC Display
  # VNC server - port is 5900 + display number
  # Display :0 = port 5900
  "-vnc"
  ":${toString (config.vncPort - 5900)}"

  # Standard VGA (compatible with all QEMU builds including minimal ones)
  "-vga"
  "std"

  # Input Devices
  "-device"
  "virtio-keyboard"
  "-usb"
  "-device"
  "usb-tablet,bus=usb-bus.0" # Absolute positioning for mouse
]
