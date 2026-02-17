# examples/http-server/helper-scripts.nix
#
# Helper scripts for the http-server example.
# These are installed to result/bin/ via microvm.binScripts.

{ pkgs, config }:

{
  # connect-serial: Connect to ttyS0 for early boot/debug
  connect-serial = ''
    #!/usr/bin/env bash
    echo "Connecting to serial console (ttyS0) on port ${toString config.serialPort}..."
    echo "Use this for kernel messages and early boot debugging."
    echo "Press Ctrl+C to disconnect."
    echo ""
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.serialPort}
  '';

  # connect-console: Connect to hvc0 for interactive use
  connect-console = ''
    #!/usr/bin/env bash
    echo "Connecting to virtio console (hvc0) on port ${toString config.virtioConsolePort}..."
    echo "Use this for interactive sessions (faster than serial)."
    echo "Press Ctrl+C to disconnect."
    echo ""
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.virtioConsolePort}
  '';

  # curl-test: Quick HTTP connectivity test
  curl-test = ''
    #!/usr/bin/env bash
    set -euo pipefail

    HTTP_PORT="${toString config.httpPortUser}"

    echo "Testing HTTP endpoints on localhost:$HTTP_PORT..."
    echo ""

    echo "GET / :"
    ${pkgs.curl}/bin/curl -s "http://localhost:$HTTP_PORT/" | head -5
    echo ""

    echo "GET /health :"
    ${pkgs.curl}/bin/curl -s "http://localhost:$HTTP_PORT/health"
    echo ""

    echo "GET /api/info :"
    ${pkgs.curl}/bin/curl -s "http://localhost:$HTTP_PORT/api/info" | ${pkgs.jq}/bin/jq .
  '';

  # measure-boot: Measure time from VM start to HTTP response
  measure-boot = ''
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    HTTP_PORT="${toString config.httpPortUser}"
    TIMEOUT="${toString config.bootTimeout}"

    echo "Measuring boot-to-serve time..."
    echo ""

    # Kill any existing instance
    pkill -f "process=http-server" 2>/dev/null || true
    sleep 1

    START_TIME=$(date +%s.%N)

    # Start VM in background
    "$SCRIPT_DIR/microvm-run" &
    VM_PID=$!

    # Poll for HTTP response
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
      if ${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HTTP_PORT/health" 2>/dev/null | grep -q "200"; then
        END_TIME=$(date +%s.%N)
        BOOT_TIME=$(echo "$END_TIME - $START_TIME" | ${pkgs.bc}/bin/bc)
        echo "Boot-to-serve: ''${BOOT_TIME}s"
        kill $VM_PID 2>/dev/null || true
        wait $VM_PID 2>/dev/null || true
        exit 0
      fi
      sleep 0.5
      ELAPSED=$((ELAPSED + 1))
    done

    echo "Timeout after ''${TIMEOUT}s"
    kill $VM_PID 2>/dev/null || true
    wait $VM_PID 2>/dev/null || true
    exit 1
  '';

  # run-test: Full automated test suite
  run-test = ''
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    HTTP_PORT="${toString config.httpPortUser}"
    SERIAL_PORT="${toString config.serialPort}"
    VIRTIO_PORT="${toString config.virtioConsolePort}"
    POLL_INTERVAL="${toString config.pollInterval}"
    PORT_TIMEOUT="${toString config.portTimeout}"

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    pass() { echo -e "  ''${GREEN}✓ $1''${NC}"; }
    fail() { echo -e "  ''${RED}✗ $1''${NC}"; exit 1; }
    info() { echo -e "  ''${YELLOW}• $1''${NC}"; }

    cleanup() {
      echo ""
      echo "Cleaning up..."
      if [ -n "''${VM_PID:-}" ] && kill -0 "$VM_PID" 2>/dev/null; then
        "$SCRIPT_DIR/microvm-shutdown" 2>/dev/null || kill "$VM_PID" 2>/dev/null || true
        wait "$VM_PID" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    echo "════════════════════════════════════════════════════════════════"
    echo "           http-server - Automated Test Suite"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    # Pre-flight: check ports are free
    if ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; then
      fail "Port $SERIAL_PORT already in use"
    fi
    if ${pkgs.netcat}/bin/nc -z localhost "$HTTP_PORT" 2>/dev/null; then
      fail "Port $HTTP_PORT already in use"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "1. Starting MicroVM..."
    # ─────────────────────────────────────────────────────────────────
    START_TIME=$(date +%s.%N)
    "$SCRIPT_DIR/microvm-run" &
    VM_PID=$!
    info "VM started with PID $VM_PID"

    # ─────────────────────────────────────────────────────────────────
    echo "2. Waiting for serial port $SERIAL_PORT..."
    # ─────────────────────────────────────────────────────────────────
    ELAPSED=0
    while ! ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; do
      if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
        fail "Timeout waiting for serial port"
      fi
      sleep $POLL_INTERVAL
      ELAPSED=$((ELAPSED + POLL_INTERVAL))
    done
    pass "Serial port listening"

    # ─────────────────────────────────────────────────────────────────
    echo "3. Waiting for HTTP port $HTTP_PORT..."
    # ─────────────────────────────────────────────────────────────────
    ELAPSED=0
    while ! ${pkgs.netcat}/bin/nc -z localhost "$HTTP_PORT" 2>/dev/null; do
      if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
        fail "Timeout waiting for HTTP port"
      fi
      sleep $POLL_INTERVAL
      ELAPSED=$((ELAPSED + POLL_INTERVAL))
    done
    pass "HTTP port listening"

    # ─────────────────────────────────────────────────────────────────
    echo "4. Testing HTTP /health endpoint..."
    # ─────────────────────────────────────────────────────────────────
    RESPONSE=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HTTP_PORT/health" || echo "000")
    if [ "$RESPONSE" = "200" ]; then
      END_TIME=$(date +%s.%N)
      BOOT_TIME=$(echo "$END_TIME - $START_TIME" | ${pkgs.bc}/bin/bc)
      pass "HTTP 200 OK (boot-to-serve: ''${BOOT_TIME}s)"
    else
      fail "HTTP returned $RESPONSE (expected 200)"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "5. Testing HTTP / (index page)..."
    # ─────────────────────────────────────────────────────────────────
    BODY=$(${pkgs.curl}/bin/curl -s "http://localhost:$HTTP_PORT/")
    if echo "$BODY" | grep -q "Hello from MicroVM"; then
      pass "Index page contains expected content"
    else
      fail "Index page missing expected content"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "6. Testing HTTP /api/info (JSON endpoint)..."
    # ─────────────────────────────────────────────────────────────────
    JSON=$(${pkgs.curl}/bin/curl -s "http://localhost:$HTTP_PORT/api/info")
    if echo "$JSON" | grep -q '"hostname"' && echo "$JSON" | grep -q '"time"'; then
      pass "JSON API returns expected fields"
    else
      fail "JSON API missing expected fields"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "7. Testing virtio console port $VIRTIO_PORT..."
    # ─────────────────────────────────────────────────────────────────
    if ${pkgs.netcat}/bin/nc -z localhost "$VIRTIO_PORT" 2>/dev/null; then
      pass "Virtio console port listening"
    else
      info "Virtio console port not available (may be expected)"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "8. Shutting down VM..."
    # ─────────────────────────────────────────────────────────────────
    "$SCRIPT_DIR/microvm-shutdown" 2>/dev/null || true
    sleep 2

    if ! kill -0 "$VM_PID" 2>/dev/null; then
      pass "VM shutdown complete"
    else
      info "VM still running, will be killed by cleanup"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo -e "''${GREEN}All tests passed! Boot-to-serve: ''${BOOT_TIME}s''${NC}"
    echo "════════════════════════════════════════════════════════════════"
  '';
}
