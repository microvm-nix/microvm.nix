# examples/graphics/config.nix
#
# Shared configuration variables for the graphics example.
#
# This imports from the centralized constants.nix to ensure consistent
# port allocations across all examples (enabling concurrent testing).
#
# Note: This example uses cloud-hypervisor with waypipe for display forwarding.
# VNC port is reserved in case cloud-hypervisor's VNC feature is enabled.

let
  # Import centralized constants
  constants = import ../lib/constants.nix;
in
constants.graphics
