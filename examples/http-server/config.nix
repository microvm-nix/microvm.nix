# examples/http-server/config.nix
#
# Configuration bridge to centralized constants.
# This pattern enables concurrent test execution without port conflicts.

let
  constants = import ../lib/constants.nix;
in
constants.http-server
