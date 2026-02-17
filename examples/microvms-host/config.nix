# examples/microvms-host/config.nix
#
# Shared configuration variables for the microvms-host example.
#
# This imports from the centralized constants.nix to ensure consistent
# port allocations across all examples (enabling concurrent testing).
#
# Note: This example has longer timeouts due to nested VM startup.

let
  # Import centralized constants
  constants = import ../lib/constants.nix;
in
constants.microvms-host
