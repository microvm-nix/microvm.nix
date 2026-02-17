# examples/valkey-server/helper-scripts.nix
#
# Helper scripts for the valkey-server example.

{ pkgs, config }:

{
  # connect-serial
  connect-serial = ''
    #!/usr/bin/env bash
    echo "Connecting to serial console (ttyS0) on port ${toString config.serialPort}..."
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.serialPort}
  '';

  # connect-console
  connect-console = ''
    #!/usr/bin/env bash
    echo "Connecting to virtio console (hvc0) on port ${toString config.virtioConsolePort}..."
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.virtioConsolePort}
  '';

  # valkey-test: Quick connectivity test
  valkey-test = ''
    #!/usr/bin/env bash
    set -euo pipefail

    VALKEY_PORT="${toString config.valkeyPortUser}"

    echo "Testing Valkey on localhost:$VALKEY_PORT..."
    echo ""

    echo "PING:"
    ${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT PING

    echo ""
    echo "SET/GET:"
    ${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT SET test:key "hello-microvm"
    ${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT GET test:key

    echo ""
    echo "INFO (server section):"
    ${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT INFO server | head -10
  '';

  # valkey-benchmark: Performance benchmark
  valkey-benchmark = ''
    #!/usr/bin/env bash
    set -euo pipefail

    VALKEY_PORT="${toString config.valkeyPortUser}"

    echo "Running Valkey benchmark on localhost:$VALKEY_PORT..."
    echo ""

    ${pkgs.valkey}/bin/valkey-benchmark \
      -h localhost \
      -p $VALKEY_PORT \
      -q \
      -n 10000 \
      -c 10 \
      -t ping,set,get
  '';

  # measure-boot
  measure-boot = ''
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    VALKEY_PORT="${toString config.valkeyPortUser}"
    TIMEOUT="${toString config.bootTimeout}"

    echo "Measuring boot-to-PONG time..."

    pkill -f "process=valkey-server" 2>/dev/null || true
    sleep 1

    START_TIME=$(date +%s.%N)

    "$SCRIPT_DIR/microvm-run" &
    VM_PID=$!

    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
      RESPONSE=$(${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT PING 2>/dev/null || echo "")
      if [ "$RESPONSE" = "PONG" ]; then
        END_TIME=$(date +%s.%N)
        BOOT_TIME=$(echo "$END_TIME - $START_TIME" | ${pkgs.bc}/bin/bc)
        echo "Boot-to-PONG: ''${BOOT_TIME}s"
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
    VALKEY_PORT="${toString config.valkeyPortUser}"
    SERIAL_PORT="${toString config.serialPort}"
    VIRTIO_PORT="${toString config.virtioConsolePort}"
    POLL_INTERVAL="${toString config.pollInterval}"
    PORT_TIMEOUT="${toString config.portTimeout}"

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
    echo "           valkey-server - Automated Test Suite"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    # Pre-flight
    if ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; then
      fail "Port $SERIAL_PORT already in use"
    fi
    if ${pkgs.netcat}/bin/nc -z localhost "$VALKEY_PORT" 2>/dev/null; then
      fail "Port $VALKEY_PORT already in use"
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
    echo "3. Waiting for Valkey port $VALKEY_PORT..."
    # ─────────────────────────────────────────────────────────────────
    ELAPSED=0
    while ! ${pkgs.netcat}/bin/nc -z localhost "$VALKEY_PORT" 2>/dev/null; do
      if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
        fail "Timeout waiting for Valkey port"
      fi
      sleep $POLL_INTERVAL
      ELAPSED=$((ELAPSED + POLL_INTERVAL))
    done
    pass "Valkey port listening"

    # ─────────────────────────────────────────────────────────────────
    echo "4. Testing PING..."
    # ─────────────────────────────────────────────────────────────────
    RESPONSE=$(${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT PING 2>/dev/null || echo "FAIL")
    if [ "$RESPONSE" = "PONG" ]; then
      END_TIME=$(date +%s.%N)
      BOOT_TIME=$(echo "$END_TIME - $START_TIME" | ${pkgs.bc}/bin/bc)
      pass "PONG received (boot-to-serve: ''${BOOT_TIME}s)"
    else
      fail "PING failed: $RESPONSE"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "5. Testing SET/GET..."
    # ─────────────────────────────────────────────────────────────────
    TEST_KEY="test:microvm:$$"
    TEST_VALUE="value-$(date +%s)"

    ${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT SET "$TEST_KEY" "$TEST_VALUE" >/dev/null
    RETRIEVED=$(${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT GET "$TEST_KEY" 2>/dev/null)

    if [ "$RETRIEVED" = "$TEST_VALUE" ]; then
      pass "SET/GET working"
    else
      fail "SET/GET failed: expected '$TEST_VALUE', got '$RETRIEVED'"
    fi

    # Cleanup test key
    ${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT DEL "$TEST_KEY" >/dev/null

    # ─────────────────────────────────────────────────────────────────
    echo "6. Testing INFO command..."
    # ─────────────────────────────────────────────────────────────────
    INFO=$(${pkgs.valkey}/bin/valkey-cli -p $VALKEY_PORT INFO server 2>/dev/null | head -3)
    if echo "$INFO" | grep -q "valkey_version\|redis_version"; then
      pass "INFO returns server version"
    else
      info "INFO output unexpected: $INFO"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "7. Running quick benchmark..."
    # ─────────────────────────────────────────────────────────────────
    BENCH=$(${pkgs.valkey}/bin/valkey-benchmark -p $VALKEY_PORT -q -n 1000 -c 5 -t ping 2>/dev/null | head -1)
    if echo "$BENCH" | grep -q "requests per second"; then
      pass "Benchmark: $BENCH"
    else
      info "Benchmark output: $BENCH"
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
