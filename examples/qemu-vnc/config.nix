# examples/qemu-vnc/config.nix
#
# Shared configuration variables for the qemu-vnc example.
#
# This imports from the centralized constants.nix to ensure consistent
# port allocations across all examples (enabling concurrent testing).

let
  # Import centralized constants
  constants = import ../lib/constants.nix;
in
constants.qemu-vnc
