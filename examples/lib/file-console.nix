# examples/lib/file-console.nix
#
# File-based console testing for hypervisors that don't support socket consoles.
# Used for cloud-hypervisor which only supports: off, tty, pty, file=<path>, null
#
# This module provides test scripts that:
# 1. Create a temp directory with mktemp -d
# 2. Run microvm-run with stdout redirected to a log file
# 3. Poll the log file for a boot marker (default: "login:")
# 4. Shutdown via SIGTERM
# 5. Clean up temp directory on exit
#
# Usage:
#   let
#     constants = import ../lib/constants.nix;
#     config = constants.graphics;
#     fileConsole = import ../lib/file-console.nix { inherit pkgs config; };
#   in
#   {
#     microvm.binScripts = {
#       run-test = fileConsole.makeFileConsoleTestScript {
#         name = "graphics";
#         processPattern = "cloud-hypervisor";
#       };
#     };
#   }
#
# The `config` parameter expects an attrset with:
#   - pollInterval :: Int
#   - bootTimeout :: Int

{ pkgs, config }:

rec {
  # File-Based Test Script Generator

  /*
    makeFileConsoleTestScript - Generate a test script using file-based console

    This is for hypervisors like cloud-hypervisor that send serial output to
    stdout (--serial tty) but don't support interactive socket consoles.

    Parameters:
      name :: String - Test name (for output headers)
      bootMarker :: String - String to grep for in log (default: "login:")
      processPattern :: String - Pattern for pgrep to verify hypervisor (optional)
      extraTests :: String - Additional test commands (bash) inserted before shutdown

    Returns:
      String - Complete bash test script
  */
  makeFileConsoleTestScript =
    {
      name,
      bootMarker ? "login:",
      processPattern ? null,
      extraTests ? "",
    }:
    ''
      #!/usr/bin/env bash
      set -euo pipefail

      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
      TEMP_DIR=""

      cleanup() {
        echo ""
        if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
          info "Cleaning up VM (PID: $VM_PID)..."
          kill "$VM_PID" 2>/dev/null || true
          wait "$VM_PID" 2>/dev/null || true
        fi
        if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
          rm -rf "$TEMP_DIR"
        fi
      }
      trap cleanup EXIT INT TERM

      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║        ${name} - Automated Test Suite (File Console)"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      # ─────────────────────────────────────────────────────────────────
      echo "1. Creating temp directory..."
      # ─────────────────────────────────────────────────────────────────
      TEMP_DIR=$(mktemp -d /tmp/microvm-${name}-XXXXXX)
      CONSOLE_LOG="$TEMP_DIR/console.log"
      pass "Temp directory: $TEMP_DIR"

      # ─────────────────────────────────────────────────────────────────
      echo "2. Starting MicroVM..."
      # ─────────────────────────────────────────────────────────────────
      # Redirect stdout/stderr to log file to capture serial output
      "$SCRIPT_DIR/microvm-run" > "$CONSOLE_LOG" 2>&1 &
      VM_PID=$!
      info "VM started with PID $VM_PID"
      info "Console log: $CONSOLE_LOG"

      # ─────────────────────────────────────────────────────────────────
      echo "3. Waiting for boot marker (\"${bootMarker}\")..."
      # ─────────────────────────────────────────────────────────────────
      BOOT_TIMEOUT=${toString config.bootTimeout}
      POLL_INTERVAL=${toString config.pollInterval}
      ELAPSED=0
      BOOTED=false

      while [ $ELAPSED -lt $BOOT_TIMEOUT ]; do
        # Check if VM is still running
        if ! kill -0 "$VM_PID" 2>/dev/null; then
          fail "VM process exited unexpectedly"
          echo "Last 20 lines of console log:"
          tail -20 "$CONSOLE_LOG" 2>/dev/null || echo "(no output)"
          exit 1
        fi

        # Check for boot marker in log
        if grep -q "${bootMarker}" "$CONSOLE_LOG" 2>/dev/null; then
          BOOTED=true
          break
        fi

        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))

        # Show progress every 10 seconds
        if [ $((ELAPSED % 10)) -eq 0 ]; then
          info "Waiting for boot... (''${ELAPSED}s/''${BOOT_TIMEOUT}s)"
        fi
      done

      if [ "$BOOTED" = true ]; then
        pass "Boot marker found after ''${ELAPSED}s"
      else
        fail "Timeout waiting for boot marker after ''${BOOT_TIMEOUT}s"
        echo "Last 30 lines of console log:"
        tail -30 "$CONSOLE_LOG" 2>/dev/null || echo "(no output)"
        exit 1
      fi

      ${
        if processPattern != null then
          ''
            # ─────────────────────────────────────────────────────────────────
            echo "4. Verifying hypervisor process..."
            # ─────────────────────────────────────────────────────────────────
            if pgrep -f "${processPattern}" >/dev/null 2>&1; then
              pass "${processPattern} process is running"
            else
              fail "${processPattern} process not found"
            fi
          ''
        else
          ""
      }

      ${extraTests}

      # ─────────────────────────────────────────────────────────────────
      echo "5. Shutting down VM..."
      # ─────────────────────────────────────────────────────────────────
      kill "$VM_PID" 2>/dev/null || true

      # Wait for clean exit (up to 10 seconds)
      SHUTDOWN_TIMEOUT=10
      SHUTDOWN_ELAPSED=0
      while kill -0 "$VM_PID" 2>/dev/null && [ $SHUTDOWN_ELAPSED -lt $SHUTDOWN_TIMEOUT ]; do
        sleep 1
        SHUTDOWN_ELAPSED=$((SHUTDOWN_ELAPSED + 1))
      done

      if ! kill -0 "$VM_PID" 2>/dev/null; then
        pass "VM shutdown complete"
      else
        info "VM still running after ''${SHUTDOWN_TIMEOUT}s, sending SIGKILL..."
        kill -9 "$VM_PID" 2>/dev/null || true
        wait "$VM_PID" 2>/dev/null || true
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

  # Helper Scripts

  /*
    makeFileConsoleInfoScript - Generate script showing console info

    Returns:
      String - Bash script with console access instructions
  */
  makeFileConsoleInfoScript = ''
    #!/usr/bin/env bash
    echo "Console Information"
    echo "═══════════════════"
    echo ""
    echo "This VM uses file-based console output."
    echo "Serial output goes to stdout when running microvm-run."
    echo ""
    echo "To capture console output:"
    echo "  ./microvm-run > console.log 2>&1 &"
    echo "  tail -f console.log"
    echo ""
    echo "To run interactively (console in terminal):"
    echo "  ./microvm-run"
  '';
}
