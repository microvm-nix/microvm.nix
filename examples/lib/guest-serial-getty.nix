# examples/lib/guest-serial-getty.nix
#
# Guest NixOS configuration for serial console access.
# Enables getty on ttyS0 with autologin for automated testing.
#
# IMPORTANT: This configuration is optimized for automated testing.
# We disable extra getty output to ensure clean serial communication
# for the echo/grep boot detection logic in test scripts.
#
# Usage:
#   imports = [ ../lib/guest-serial-getty.nix ];
#
# What this provides:
#   - Kernel console output on ttyS0
#   - Getty (login prompt) on ttyS0
#   - Autologin as root
#   - Clean output (no help text or greeting banners)
#   - Empty root password for testing

{ lib, ... }:

{
  # Kernel Console Configuration
  # Direct kernel output to serial port at 115200 baud
  boot.kernelParams = [
    "console=ttyS0,115200"
  ];

  # Getty Service
  # Run login prompt on serial console
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # Autologin for testing convenience
  services.getty.autologinUser = "root";

  # Clean Serial Output for Automated Testing
  # The boot detection loop sends "echo BOOT_TEST_$$" and greps for the response.
  # Extra getty output can interfere with this:
  #   - helpLine: "Type 'help' for available commands" noise
  #   - greetingLine: Additional banner text
  #   - Login prompts if autologin isn't instantaneous
  #
  # By clearing these, we get clean shell output that's easy to parse.
  services.getty.helpLine = "";
  services.getty.greetingLine = "";

  # Authentication
  # Empty root password for testing (INSECURE - testing only!)
  users.users.root.password = lib.mkDefault "";
}
