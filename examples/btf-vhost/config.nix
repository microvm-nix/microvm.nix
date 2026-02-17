# examples/btf-vhost/config.nix
#
# Shared configuration variables for the BTF + vhost MicroVM example.
#
# This imports from the centralized constants.nix to ensure consistent
# port allocations across all examples (enabling concurrent testing).
#
# Edit these values to customize the network and console setup.

let
  # Import centralized constants
  constants = import ../lib/constants.nix;
in
constants.btf-vhost
