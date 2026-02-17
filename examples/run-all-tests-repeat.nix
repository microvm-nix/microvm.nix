# examples/run-all-tests-repeat.nix
#
# Runs all example tests multiple times (default: 3).
# Useful for catching intermittent failures.
#
# Usage:
#   nix run .#test-all-examples-repeat
#   nix run .#test-all-examples-repeat -- 5              # Run 5 times
#   nix run .#test-all-examples-repeat -- 3 --parallel   # Pass args to test runner

{ pkgs }:

let
  testAllExamples = import ./run-all-tests.nix { inherit pkgs; };
in

pkgs.writeShellApplication {
  name = "test-all-examples-repeat";

  runtimeInputs = [ testAllExamples ];

  text = ''
    set -euo pipefail

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    REPEAT=3
    EXTRA_ARGS=""

    # Parse first arg as repeat count if it's a number
    if [[ $# -gt 0 && $1 =~ ^[0-9]+$ ]]; then
      REPEAT=$1
      shift
    fi

    # Remaining args passed to test-all-examples
    EXTRA_ARGS="$*"

    echo -e "''${CYAN}╔═══════════════════════════════════════════════════════════════╗''${NC}"
    echo -e "''${CYAN}║           MicroVM Examples - Repeated Test Suite              ║''${NC}"
    echo -e "''${CYAN}╚═══════════════════════════════════════════════════════════════╝''${NC}"
    echo ""
    echo "Running tests $REPEAT times..."
    echo ""

    PASSED=0
    FAILED=0

    for i in $(seq 1 "$REPEAT"); do
      echo -e "''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
      echo -e "''${CYAN}Run $i of $REPEAT''${NC}"
      echo -e "''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
      echo ""

      if test-all-examples "$EXTRA_ARGS"; then
        echo -e "''${GREEN}✓ Run $i passed''${NC}"
        PASSED=$((PASSED + 1))
      else
        echo -e "''${RED}✗ Run $i failed''${NC}"
        FAILED=$((FAILED + 1))
      fi
      echo ""
    done

    echo -e "''${CYAN}═══════════════════════════════════════════════════════════════''${NC}"
    echo -e "''${CYAN}                    Repeat Summary''${NC}"
    echo -e "''${CYAN}═══════════════════════════════════════════════════════════════''${NC}"
    echo -e "''${GREEN}Passed: $PASSED/$REPEAT''${NC}"
    if [ $FAILED -gt 0 ]; then
      echo -e "''${RED}Failed: $FAILED/$REPEAT''${NC}"
      exit 1
    else
      echo -e "''${GREEN}All $REPEAT runs passed!''${NC}"
      exit 0
    fi
  '';
}
