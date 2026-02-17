# examples/valkey-server/config.nix
#
# Configuration bridge to centralized constants.

let
  constants = import ../lib/constants.nix;
in
constants.valkey-server
