# examples/lib/test-lib.nix
#
# Shared test helper functions for MicroVM examples.
# Provides reusable test script generators and console connection utilities.
#
# Usage:
#   let
#     constants = import ../lib/constants.nix;
#     config = constants.btf-vhost;
#     testLib = import ../lib/test-lib.nix { inherit pkgs config; };
#   in
#   {
#     microvm.binScripts = {
#       run-test = testLib.makeTestScript {
#         name = "btf-vhost";
#         hasVirtioConsole = true;
#         extraTests = ''
#           # Custom tests here
#         '';
#       };
#       connect-serial = testLib.makeSerialConnectScript;
#     };
#   }
#
# The `config` parameter expects an attrset with:
#   - serialPort :: Int
#   - virtioConsolePort :: Int (optional, for hasVirtioConsole)
#   - pollInterval :: Int
#   - portTimeout :: Int
#   - bootTimeout :: Int
#   - commandTimeout :: Int

{ pkgs, config }:

rec {
  # Core Test Script Generator

  /*
    makeTestScript - Generate a complete test script for a MicroVM

    Parameters:
      name :: String - Test name (for output headers)
      extraTests :: String - Additional test commands (bash) inserted before shutdown
      hasVirtioConsole :: Bool - Whether to test hvc0 (default: false)
      hasNetwork :: Bool - Whether to include network tests (default: false)
      networkTests :: String - Network-specific test commands (only if hasNetwork)

    Returns:
      String - Complete bash test script
  */
  makeTestScript =
    {
      name,
      extraTests ? "",
      hasVirtioConsole ? false,
      hasNetwork ? false,
      networkTests ? "",
    }:
    ''
      #!/usr/bin/env bash
      set -euo pipefail

      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
      SERIAL_PORT="${toString config.serialPort}"
      ${if hasVirtioConsole then ''VIRTIO_PORT="${toString config.virtioConsolePort}"'' else ""}

      # Colors for output
      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      NC='\033[0m' # No Color

      pass() { echo -e "  ''${GREEN}✓ $1''${NC}"; }
      fail() { echo -e "  ''${RED}✗ $1''${NC}"; FAILED=1; }
      info() { echo -e "  ''${YELLOW}• $1''${NC}"; }

      FAILED=0
      VM_PID=""

      cleanup() {
        echo ""
        if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
          info "Cleaning up VM (PID: $VM_PID)..."
          "$SCRIPT_DIR/microvm-shutdown" 2>/dev/null || kill "$VM_PID" 2>/dev/null || true
          wait "$VM_PID" 2>/dev/null || true
        fi
      }
      trap cleanup EXIT

      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║        ${name} - Automated Test Suite"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      # ─────────────────────────────────────────────────────────────────
      echo "1. Checking if ports are available..."
      # ─────────────────────────────────────────────────────────────────
      if ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; then
        fail "Port $SERIAL_PORT already in use - is another VM running?"
        exit 1
      fi
      pass "Serial port $SERIAL_PORT is available"

      # ─────────────────────────────────────────────────────────────────
      echo "2. Starting MicroVM..."
      # ─────────────────────────────────────────────────────────────────
      "$SCRIPT_DIR/microvm-run" &
      VM_PID=$!
      info "VM started with PID $VM_PID"

      # ─────────────────────────────────────────────────────────────────
      echo "3. Waiting for serial port..."
      # ─────────────────────────────────────────────────────────────────
      PORT_TIMEOUT=${toString config.portTimeout}
      POLL_INTERVAL=${toString config.pollInterval}
      ELAPSED=0

      while ! ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; do
        if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
          fail "Timeout waiting for serial port after ''${PORT_TIMEOUT}s"
          exit 1
        fi
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
      done
      pass "Serial port $SERIAL_PORT is listening (''${ELAPSED}s)"

      ${
        if hasVirtioConsole then
          ''
            # ─────────────────────────────────────────────────────────────────
            echo "4. Waiting for virtio console port..."
            # ─────────────────────────────────────────────────────────────────
            while ! ${pkgs.netcat}/bin/nc -z localhost "$VIRTIO_PORT" 2>/dev/null; do
              if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
                fail "Timeout waiting for virtio port after ''${PORT_TIMEOUT}s"
                exit 1
              fi
              sleep $POLL_INTERVAL
              ELAPSED=$((ELAPSED + POLL_INTERVAL))
            done
            pass "Virtio port $VIRTIO_PORT is listening"
          ''
        else
          ""
      }

      # ─────────────────────────────────────────────────────────────────
      echo "5. Waiting for system boot (testing shell response)..."
      # ─────────────────────────────────────────────────────────────────
      BOOT_TIMEOUT=${toString config.bootTimeout}
      CMD_TIMEOUT=${toString config.commandTimeout}
      ELAPSED=0
      BOOTED=false

      while [ $ELAPSED -lt $BOOT_TIMEOUT ]; do
        # Send command and check for response via serial
        RESPONSE=$(echo "echo BOOT_TEST_$$" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$SERIAL_PORT" 2>/dev/null | head -5 || true)
        if echo "$RESPONSE" | grep -q "BOOT_TEST_$$"; then
          BOOTED=true
          break
        fi
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        info "Waiting for boot... (''${ELAPSED}s/''${BOOT_TIMEOUT}s)"
      done

      if [ "$BOOTED" = true ]; then
        pass "System booted and shell is responsive (''${ELAPSED}s)"
      else
        fail "Timeout waiting for boot after ''${BOOT_TIMEOUT}s"
        exit 1
      fi

      # ─────────────────────────────────────────────────────────────────
      echo "6. Testing serial console command execution..."
      # ─────────────────────────────────────────────────────────────────
      SERIAL_RESPONSE=$(echo "uname -r" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$SERIAL_PORT" 2>/dev/null | grep -v "^#\|^$\|login:" | head -3 || true)
      if [ -n "$SERIAL_RESPONSE" ]; then
        pass "Serial console responds: $(echo "$SERIAL_RESPONSE" | head -1)"
      else
        info "Serial console response unclear (may need manual verification)"
      fi

      ${if hasNetwork then networkTests else ""}

      ${extraTests}

      # ─────────────────────────────────────────────────────────────────
      echo "7. Shutting down VM..."
      # ─────────────────────────────────────────────────────────────────
      echo "poweroff" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$SERIAL_PORT" 2>/dev/null || true
      sleep 2

      if ! kill -0 "$VM_PID" 2>/dev/null; then
        pass "VM shutdown complete"
      else
        info "VM still running, sending SIGTERM..."
        kill "$VM_PID" 2>/dev/null || true
        sleep 2
      fi

      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      if [ $FAILED -eq 0 ]; then
        echo -e "''${GREEN}All tests passed!''${NC}"
        exit 0
      else
        echo -e "''${RED}Some tests failed.''${NC}"
        exit 1
      fi
    '';

  # Console Connection Scripts

  /*
    makeSerialConnectScript - Generate script to connect to serial console

    Returns:
      String - Bash script for interactive serial connection
  */
  makeSerialConnectScript = ''
    #!/usr/bin/env bash
    echo "Connecting to serial console (ttyS0) on port ${toString config.serialPort}..."
    echo "Press Ctrl+C to disconnect."
    echo ""
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.serialPort}
  '';

  /*
    makeVirtioConnectScript - Generate script to connect to virtio console

    Returns:
      String - Bash script for interactive virtio console connection
  */
  makeVirtioConnectScript = ''
    #!/usr/bin/env bash
    echo "Connecting to virtio console (hvc0) on port ${toString config.virtioConsolePort}..."
    echo "Press Ctrl+C to disconnect."
    echo ""
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.virtioConsolePort}
  '';

  /*
    makeConsoleStatusScript - Generate script to check console port status

    Returns:
      String - Bash script showing port availability
  */
  makeConsoleStatusScript = ''
    #!/usr/bin/env bash
    echo "Console Status"
    echo "══════════════"
    echo ""
    printf "ttyS0 (serial)  port ${toString config.serialPort}: "
    if ${pkgs.netcat}/bin/nc -z localhost ${toString config.serialPort} 2>/dev/null; then
      echo "✓ listening"
    else
      echo "✗ not available"
    fi
    ${
      if config ? virtioConsolePort then
        ''
          printf "hvc0  (virtio)  port ${toString config.virtioConsolePort}: "
          if ${pkgs.netcat}/bin/nc -z localhost ${toString config.virtioConsolePort} 2>/dev/null; then
            echo "✓ listening"
          else
            echo "✗ not available"
          fi
        ''
      else
        ""
    }
  '';
}
