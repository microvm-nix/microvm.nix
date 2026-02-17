# examples/lib/guest-virtio-getty.nix
#
# Guest NixOS configuration for virtio-console (hvc0) access.
# Enables getty on hvc0 with autologin for automated testing.
#
# This uses virtio-console (hvc0) which is faster than emulated UART (ttyS0):
#   - Batched I/O via virtqueue
#   - Lower CPU overhead
#   - Supports terminal resize
#   - Requires virtio drivers (not available at very early boot)
#
# Use this for fast interactive sessions. For early boot debugging,
# combine with guest-serial-getty.nix.
#
# IMPORTANT: This configuration is optimized for automated testing.
# We disable extra getty output to ensure clean console communication
# for the echo/grep boot detection logic in test scripts.
#
# Usage:
#   imports = [ ../lib/guest-virtio-getty.nix ];

{ lib, ... }:

{
  # Kernel Console Configuration
  # Direct kernel output to virtio-console (hvc0)
  # This becomes the primary console after virtio drivers load
  boot.kernelParams = lib.mkDefault [
    "console=hvc0"
  ];

  # Getty Service
  # Run login prompt on virtio-console
  systemd.services."serial-getty@hvc0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # Autologin for testing convenience
  services.getty.autologinUser = lib.mkDefault "root";

  # Clean Console Output for Automated Testing
  services.getty.helpLine = lib.mkDefault "";
  services.getty.greetingLine = lib.mkDefault "";

  # Authentication
  users.users.root.password = lib.mkDefault "";
}
