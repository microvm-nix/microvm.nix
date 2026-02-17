# examples/lib/socket-console.nix
#
# Unix domain socket console helpers for hypervisors that don't support TCP.
# Used by cloud-hypervisor, firecracker, and other hypervisors.
#
# Unix sockets have several advantages over TCP:
# - No port conflicts (unique temp paths)
# - Faster (no TCP/IP stack overhead)
# - More secure (filesystem permissions)
# - Simpler cleanup (just delete the file)
#
# Usage:
#   let
#     socketLib = import ../lib/socket-console.nix { inherit pkgs; };
#   in
#   {
#     microvm.binScripts = {
#       run-test = socketLib.makeSocketTestScript {
#         name = "graphics";
#         # ... other options
#       };
#     };
#   }

{
  pkgs,
  config ? { },
}:

rec {
  # Socket Setup Helpers

  /*
    setupSocketDir - Bash snippet to create temp directory for sockets

    Creates a unique temp directory and sets up cleanup trap.
    Sets SOCKET_DIR environment variable.

    Returns:
      String - Bash script snippet
  */
  setupSocketDir = ''
    # Create unique temp directory for socket files
    SOCKET_DIR=$(mktemp -d /tmp/microvm-test-XXXXXX)

    # Cleanup on exit, error, or interrupt
    cleanup_socket_dir() {
      if [ -d "$SOCKET_DIR" ]; then
        rm -rf "$SOCKET_DIR"
      fi
    }
    trap cleanup_socket_dir EXIT INT TERM
  '';

  /*
    waitForSocket - Bash snippet to wait for a Unix socket to exist

    Parameters (via environment variables):
      SOCKET_PATH - Path to socket file
      SOCKET_TIMEOUT - Max seconds to wait (default: 120)
      POLL_INTERVAL - Seconds between checks (default: 1)

    Returns:
      String - Bash script snippet
  */
  waitForSocket = ''
    wait_for_socket() {
      local socket_path="$1"
      local timeout="''${2:-120}"
      local poll_interval="''${3:-1}"
      local elapsed=0

      while [ ! -S "$socket_path" ]; do
        if [ $elapsed -ge $timeout ]; then
          echo "Timeout waiting for socket: $socket_path"
          return 1
        fi
        sleep $poll_interval
        elapsed=$((elapsed + poll_interval))
      done
      return 0
    }
  '';

  /*
    sendToSocket - Bash snippet to send command to Unix socket and get response

    Uses socat for socket communication.

    Returns:
      String - Bash script snippet
  */
  sendToSocket = ''
    send_to_socket() {
      local socket_path="$1"
      local command="$2"
      local timeout="''${3:-5}"

      echo "$command" | timeout $timeout ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$socket_path" 2>/dev/null
    }
  '';

  # Socket Test Script Generator

  /*
    makeSocketTestScript - Generate a test script using Unix socket console

    Parameters:
      name :: String - Test name (for output headers)
      socketName :: String - Socket filename (default: "console.sock")
      extraTests :: String - Additional test commands (bash)
      bootTimeout :: Int - Max seconds to wait for boot (default: 180)
      pollInterval :: Int - Seconds between polls (default: 1)
      commandTimeout :: Int - Timeout for individual commands (default: 5)

    Returns:
      String - Complete bash test script
  */
  makeSocketTestScript =
    {
      name,
      socketName ? "console.sock",
      extraTests ? "",
      bootTimeout ? 180,
      pollInterval ? 1,
      commandTimeout ? 5,
    }:
    ''
      #!/usr/bin/env bash
      set -euo pipefail

      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

      # Colors for output
      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      NC='\033[0m'

      pass() { echo -e "  ''${GREEN}✓ $1''${NC}"; }
      fail() { echo -e "  ''${RED}✗ $1''${NC}"; FAILED=1; }
      info() { echo -e "  ''${YELLOW}• $1''${NC}"; }

      FAILED=0
      VM_PID=""

      ${setupSocketDir}

      CONSOLE_SOCKET="$SOCKET_DIR/${socketName}"

      ${waitForSocket}
      ${sendToSocket}

      cleanup() {
        echo ""
        if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
          info "Cleaning up VM (PID: $VM_PID)..."
          "$SCRIPT_DIR/microvm-shutdown" 2>/dev/null || kill "$VM_PID" 2>/dev/null || true
          wait "$VM_PID" 2>/dev/null || true
        fi
        cleanup_socket_dir
      }
      trap cleanup EXIT INT TERM

      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║        ${name} - Automated Test Suite (Unix Socket)"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      # ─────────────────────────────────────────────────────────────────
      echo "1. Setting up socket directory..."
      # ─────────────────────────────────────────────────────────────────
      pass "Socket directory: $SOCKET_DIR"

      # ─────────────────────────────────────────────────────────────────
      echo "2. Starting MicroVM..."
      # ─────────────────────────────────────────────────────────────────
      # Export socket path for the VM to use
      export MICROVM_CONSOLE_SOCKET="$CONSOLE_SOCKET"
      "$SCRIPT_DIR/microvm-run" &
      VM_PID=$!
      info "VM started with PID $VM_PID"

      # ─────────────────────────────────────────────────────────────────
      echo "3. Waiting for console socket..."
      # ─────────────────────────────────────────────────────────────────
      if wait_for_socket "$CONSOLE_SOCKET" ${toString bootTimeout} ${toString pollInterval}; then
        pass "Console socket is ready"
      else
        fail "Console socket not available after ${toString bootTimeout}s"
        exit 1
      fi

      # ─────────────────────────────────────────────────────────────────
      echo "4. Waiting for system boot (testing shell response)..."
      # ─────────────────────────────────────────────────────────────────
      BOOT_TIMEOUT=${toString bootTimeout}
      POLL_INTERVAL=${toString pollInterval}
      CMD_TIMEOUT=${toString commandTimeout}
      ELAPSED=0
      BOOTED=false

      while [ $ELAPSED -lt $BOOT_TIMEOUT ]; do
        RESPONSE=$(send_to_socket "$CONSOLE_SOCKET" "echo BOOT_TEST_$$" $CMD_TIMEOUT || true)
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
      echo "5. Testing console command execution..."
      # ─────────────────────────────────────────────────────────────────
      CONSOLE_RESPONSE=$(send_to_socket "$CONSOLE_SOCKET" "uname -r" $CMD_TIMEOUT || true)
      if [ -n "$CONSOLE_RESPONSE" ]; then
        pass "Console responds: $(echo "$CONSOLE_RESPONSE" | head -1)"
      else
        info "Console response unclear (may need manual verification)"
      fi

      ${extraTests}

      # ─────────────────────────────────────────────────────────────────
      echo "6. Shutting down VM..."
      # ─────────────────────────────────────────────────────────────────
      send_to_socket "$CONSOLE_SOCKET" "poweroff" $CMD_TIMEOUT || true
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

  # Socket Connection Scripts

  /*
    makeSocketConnectScript - Generate script to connect to Unix socket console

    Parameters:
      socketPath :: String - Path to socket (or use $MICROVM_CONSOLE_SOCKET)

    Returns:
      String - Bash script for interactive socket connection
  */
  makeSocketConnectScript =
    {
      socketPath ? null,
    }:
    ''
      #!/usr/bin/env bash
      SOCKET_PATH="''${1:-${if socketPath != null then socketPath else "$MICROVM_CONSOLE_SOCKET"}}"

      if [ -z "$SOCKET_PATH" ]; then
        echo "Usage: $0 <socket-path>"
        echo "Or set MICROVM_CONSOLE_SOCKET environment variable"
        exit 1
      fi

      if [ ! -S "$SOCKET_PATH" ]; then
        echo "Socket not found: $SOCKET_PATH"
        echo "Is the VM running?"
        exit 1
      fi

      echo "Connecting to console socket: $SOCKET_PATH"
      echo "Press Ctrl+C to disconnect."
      echo ""
      exec ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET_PATH"
    '';
}
