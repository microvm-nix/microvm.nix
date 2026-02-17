# examples/run-all-tests.nix
#
# All-examples test runner with pre-flight port checking.
#
# This script runs tests for all MicroVM examples, with features:
# - Pre-flight port availability check (prevents partial failures)
# - Sequential or parallel execution modes
# - Clear pass/fail summary
#
# Usage:
#   nix run .#test-all-examples
#   nix run .#test-all-examples -- --parallel
#   nix run .#test-all-examples -- console-demo btf-vhost

{ pkgs }:

let
  # Import port allocations from constants
  constants = import ./lib/constants.nix;
in

pkgs.writeShellApplication {
  name = "test-all-examples";

  runtimeInputs = with pkgs; [
    coreutils
    gnugrep
    netcat
    nix
  ];

  text = ''
    set -euo pipefail

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    PARALLEL=false
    EXAMPLES=""
    SKIP_PREFLIGHT=false

    usage() {
      echo "Usage: $0 [OPTIONS] [example1 example2 ...]"
      echo ""
      echo "Options:"
      echo "  --parallel       Run tests in parallel (concurrent VMs)"
      echo "  --skip-preflight Skip port availability check"
      echo "  --help, -h       Show this help"
      echo ""
      echo "Available examples:"
      echo "  btf-vhost       - eBPF/BTF + vhost networking (serial: ${toString constants.btf-vhost.serialPort})"
      echo "  console-demo    - Dual console demo (serial: ${toString constants.console-demo.serialPort})"
      echo "  http-server     - Nginx web server (serial: ${toString constants.http-server.serialPort}, http: ${toString constants.http-server.httpPortUser})"
      echo "  valkey-server   - Valkey cache server (serial: ${toString constants.valkey-server.serialPort}, valkey: ${toString constants.valkey-server.valkeyPortUser})"
      echo "  qemu-vnc        - QEMU VNC desktop (serial: ${toString constants.qemu-vnc.serialPort}, vnc: ${toString constants.qemu-vnc.vncPort})"
      echo "  graphics        - Wayland graphics (vnc: ${toString constants.graphics.vncPort})"
      echo "  microvms-host   - Nested VMs (serial: ${toString constants.microvms-host.serialPort})"
      echo ""
      echo "If no examples specified, runs: console-demo, http-server, valkey-server, qemu-vnc"
      echo "(btf-vhost, graphics, and microvms-host require special setup)"
    }

    # Parse args
    while [[ $# -gt 0 ]]; do
      case $1 in
        --parallel)
          PARALLEL=true
          shift
          ;;
        --skip-preflight)
          SKIP_PREFLIGHT=true
          shift
          ;;
        --help|-h)
          usage
          exit 0
          ;;
        -*)
          echo "Unknown option: $1"
          usage
          exit 1
          ;;
        *)
          EXAMPLES="$EXAMPLES $1"
          shift
          ;;
      esac
    done

    # Default to standard examples (no special setup required)
    if [ -z "$EXAMPLES" ]; then
      EXAMPLES="console-demo http-server valkey-server qemu-vnc"
    fi

    echo -e "''${CYAN}╔═══════════════════════════════════════════════════════════════╗''${NC}"
    echo -e "''${CYAN}║           MicroVM Examples - Test Suite                       ║''${NC}"
    echo -e "''${CYAN}╚═══════════════════════════════════════════════════════════════╝''${NC}"
    echo ""

    # Pre-flight Port Check
    preflight_check() {
      echo -e "''${CYAN}Pre-flight: Checking port availability...''${NC}"

      local PORTS_IN_USE=""
      local ALL_CLEAR=true

      # Port assignments from constants.nix
      declare -A EXAMPLE_PORTS
      EXAMPLE_PORTS["btf-vhost"]="${toString constants.btf-vhost.serialPort} ${toString constants.btf-vhost.virtioConsolePort}"
      EXAMPLE_PORTS["console-demo"]="${toString constants.console-demo.serialPort} ${toString constants.console-demo.virtioConsolePort}"
      EXAMPLE_PORTS["http-server"]="${toString constants.http-server.serialPort} ${toString constants.http-server.virtioConsolePort} ${toString constants.http-server.httpPortUser}"
      EXAMPLE_PORTS["valkey-server"]="${toString constants.valkey-server.serialPort} ${toString constants.valkey-server.virtioConsolePort} ${toString constants.valkey-server.valkeyPortUser}"
      EXAMPLE_PORTS["graphics"]="${toString constants.graphics.vncPort}"
      EXAMPLE_PORTS["microvms-host"]="${toString constants.microvms-host.serialPort}"
      EXAMPLE_PORTS["qemu-vnc"]="${toString constants.qemu-vnc.serialPort} ${toString constants.qemu-vnc.vncPort}"

      for example in $EXAMPLES; do
        local ports=''${EXAMPLE_PORTS[$example]:-}
        if [ -z "$ports" ]; then
          echo -e "  ''${YELLOW}• $example: unknown example (skipping port check)''${NC}"
          continue
        fi

        for port in $ports; do
          if nc -z localhost "$port" 2>/dev/null; then
            echo -e "  ''${RED}✗ Port $port ($example) is in use''${NC}"
            PORTS_IN_USE="$PORTS_IN_USE $port"
            ALL_CLEAR=false
          fi
        done
      done

      if [ "$ALL_CLEAR" = true ]; then
        echo -e "  ''${GREEN}✓ All ports available''${NC}"
        echo ""
        return 0
      else
        echo ""
        echo -e "''${RED}Pre-flight failed: ports in use:$PORTS_IN_USE''${NC}"
        echo -e "''${YELLOW}Check for running VMs: ps aux | grep -E 'qemu|firecracker|cloud-hypervisor' ''${NC}"
        echo ""
        return 1
      fi
    }

    if [ "$SKIP_PREFLIGHT" = false ]; then
      if ! preflight_check; then
        exit 1
      fi
    fi

    FAILED_EXAMPLES=""
    PASSED_EXAMPLES=""
    SKIPPED_EXAMPLES=""

    run_test() {
      local example=$1
      echo -e "''${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
      echo -e "''${YELLOW}Testing: $example''${NC}"
      echo -e "''${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"

      # Build and run test for this example
      if nix build ".#$example" --no-link 2>/dev/null; then
        RESULT_PATH=$(nix build ".#$example" --print-out-paths 2>/dev/null)
        # Try different test script names (different examples use different names)
        TEST_SCRIPT=""
        if [ -x "$RESULT_PATH/bin/run-test" ]; then
          TEST_SCRIPT="$RESULT_PATH/bin/run-test"
        elif [ -x "$RESULT_PATH/bin/microvm-test" ]; then
          TEST_SCRIPT="$RESULT_PATH/bin/microvm-test"
        fi

        if [ -n "$TEST_SCRIPT" ]; then
          if "$TEST_SCRIPT"; then
            echo -e "''${GREEN}✓ $example passed''${NC}"
            PASSED_EXAMPLES="$PASSED_EXAMPLES $example"
          else
            echo -e "''${RED}✗ $example failed''${NC}"
            FAILED_EXAMPLES="$FAILED_EXAMPLES $example"
          fi
        else
          echo -e "''${YELLOW}• $example has no test script (skipping)''${NC}"
          SKIPPED_EXAMPLES="$SKIPPED_EXAMPLES $example"
        fi
      else
        echo -e "''${RED}✗ $example failed to build''${NC}"
        FAILED_EXAMPLES="$FAILED_EXAMPLES $example"
      fi
    }

    if [ "$PARALLEL" = true ]; then
      echo -e "''${CYAN}Running tests in parallel...''${NC}"
      echo ""

      # Run tests in parallel using background jobs
      PIDS=""
      for example in $EXAMPLES; do
        (
          run_test "$example"
        ) &
        PIDS="$PIDS $!"
      done

      # Wait for all jobs
      for pid in $PIDS; do
        wait "$pid" || true
      done
    else
      echo -e "''${CYAN}Running tests sequentially...''${NC}"
      echo ""

      for example in $EXAMPLES; do
        run_test "$example"
        echo ""
      done
    fi

    # Summary
    echo ""
    echo -e "''${CYAN}═══════════════════════════════════════════════════════════════''${NC}"
    echo -e "''${CYAN}                         Summary''${NC}"
    echo -e "''${CYAN}═══════════════════════════════════════════════════════════════''${NC}"

    if [ -n "$PASSED_EXAMPLES" ]; then
      echo -e "''${GREEN}Passed:$PASSED_EXAMPLES''${NC}"
    fi

    if [ -n "$SKIPPED_EXAMPLES" ]; then
      echo -e "''${YELLOW}Skipped:$SKIPPED_EXAMPLES''${NC}"
    fi

    if [ -n "$FAILED_EXAMPLES" ]; then
      echo -e "''${RED}Failed:$FAILED_EXAMPLES''${NC}"
      exit 1
    else
      echo -e "''${GREEN}All tests passed!''${NC}"
      exit 0
    fi
  '';
}
