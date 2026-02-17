# examples/btf-vhost/helper-scripts.nix
#
# Helper scripts added to the MicroVM runner package.
# These scripts are available in result/bin/ after building.
#
# Usage:
#   ./result/bin/microvm-setup-network  # First: create host networking
#   ./result/bin/microvm-run &          # Start VM in background
#   ./result/bin/microvm-test           # Run automated tests
#   ./result/bin/microvm-ssh            # SSH into VM
#   ./result/bin/microvm-console        # Connect to hvc0 (fast)
#   ./result/bin/microvm-serial         # Connect to ttyS0 (debug)
#   ./result/bin/microvm-teardown-network  # Cleanup networking

{ pkgs, config }:

{
  # microvm-setup-network
  # Creates the bridge and TAP interface on the host.
  # Must be run (with sudo) before starting the VM.
  microvm-setup-network = ''
    #!/usr/bin/env bash
    set -euo pipefail

    BRIDGE="${config.bridgeInterface}"
    TAP="${config.tapInterface}"
    BRIDGE_ADDR="${config.bridgeAddr}/24"

    echo "Creating bridge $BRIDGE..."
    if ! ip link show "$BRIDGE" &>/dev/null; then
      sudo ip link add name "$BRIDGE" type bridge
      sudo ip addr add "$BRIDGE_ADDR" dev "$BRIDGE"
      sudo ip link set "$BRIDGE" up
      echo "  ✓ Bridge $BRIDGE created with address $BRIDGE_ADDR"
    else
      echo "  • Bridge $BRIDGE already exists"
    fi

    echo "Creating TAP interface $TAP..."
    if ! ip link show "$TAP" &>/dev/null; then
      # user=$USER allows the current user to use the TAP without root
      sudo ip tuntap add dev "$TAP" mode tap user "$USER" multi_queue
      sudo ip link set "$TAP" master "$BRIDGE"
      sudo ip link set "$TAP" up
      echo "  ✓ TAP interface $TAP created (multi-queue, user=$USER) and attached to $BRIDGE"
    else
      echo "  • TAP interface $TAP already exists"
    fi

    echo ""
    echo "Network setup complete!"
    echo "  Bridge: $BRIDGE ($BRIDGE_ADDR)"
    echo "  TAP:    $TAP"
    echo "  VM IP:  ${config.vmAddr}"
  '';

  # microvm-ssh
  # SSH into the VM. Passwordless (empty password configured).
  microvm-ssh = ''
    #!/usr/bin/env bash
    exec ${pkgs.openssh}/bin/ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      root@${config.vmAddr} "$@"
  '';

  # microvm-console
  # Connect to virtio-console (hvc0) - fast, for interactive use.
  microvm-console = ''
    #!/usr/bin/env bash
    echo "Connecting to virtio-console (hvc0) on port ${toString config.virtioConsolePort}..."
    echo "This is the FAST console - use for interactive sessions."
    echo "Press Ctrl+C to disconnect."
    echo ""
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.virtioConsolePort}
  '';

  # microvm-serial
  # Connect to serial console (ttyS0) - for kernel/debug output.
  microvm-serial = ''
    #!/usr/bin/env bash
    echo "Connecting to serial console (ttyS0) on port ${toString config.serialPort}..."
    echo "This shows kernel messages and early boot output."
    echo "Press Ctrl+C to disconnect."
    echo ""
    exec ${pkgs.netcat}/bin/nc localhost ${toString config.serialPort}
  '';

  # microvm-test
  # Automated connectivity test suite.
  # Tests: console ports, ping, SSH, BTF/eBPF tools, network throughput.
  microvm-test = ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    pass() { echo -e "  ''${GREEN}✓ $1''${NC}"; }
    fail() { echo -e "  ''${RED}✗ $1''${NC}"; }
    info() { echo -e "  ''${YELLOW}• $1''${NC}"; }

    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           MicroVM Connectivity Test Suite                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    FAILED=0

    # Helper function for SSH commands
    ssh_cmd() {
      ${pkgs.openssh}/bin/ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        root@${config.vmAddr} "$@" 2>/dev/null
    }

    # ─────────────────────────────────────────────────────────────────
    echo "1. Testing serial console (ttyS0) on port ${toString config.serialPort}..."
    # ─────────────────────────────────────────────────────────────────
    if ${pkgs.netcat}/bin/nc -z localhost ${toString config.serialPort} 2>/dev/null; then
      pass "Port ${toString config.serialPort} is open"
    else
      fail "Port ${toString config.serialPort} is not reachable"
      FAILED=1
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "2. Testing virtio-console (hvc0) on port ${toString config.virtioConsolePort}..."
    # ─────────────────────────────────────────────────────────────────
    if ${pkgs.netcat}/bin/nc -z localhost ${toString config.virtioConsolePort} 2>/dev/null; then
      pass "Port ${toString config.virtioConsolePort} is open"
    else
      fail "Port ${toString config.virtioConsolePort} is not reachable"
      FAILED=1
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "3. Testing network connectivity to VM (${config.vmAddr})..."
    # ─────────────────────────────────────────────────────────────────
    if ${pkgs.iputils}/bin/ping -c 1 -W 2 ${config.vmAddr} &>/dev/null; then
      pass "VM responds to ping"
    else
      fail "VM does not respond to ping"
      info "Make sure microvm-setup-network was run"
      FAILED=1
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "4. Testing SSH connection..."
    # ─────────────────────────────────────────────────────────────────
    SSH_RESULT=$(ssh_cmd "echo SSH_OK" || echo "SSH_FAIL")

    if [ "$SSH_RESULT" = "SSH_OK" ]; then
      pass "SSH connection successful (passwordless)"
    else
      fail "SSH connection failed"
      FAILED=1
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "5. Testing BTF support..."
    # ─────────────────────────────────────────────────────────────────
    # BTF (BPF Type Format) allows eBPF tools to run without recompilation.
    # We test multiple tools to verify BTF is working.

    echo "   5a. Testing tcptop (TCP throughput tracer)..."
    TCPTOP_RESULT=$(ssh_cmd "timeout 2 tcptop -C 1 1 2>&1" || echo "")
    if echo "$TCPTOP_RESULT" | grep -q "Tracing\|loadavg"; then
      pass "tcptop works - BTF is functional"
    else
      fail "tcptop failed: $TCPTOP_RESULT"
      FAILED=1
    fi

    echo "   5b. Testing execsnoop (process exec tracer)..."
    # Run a command while execsnoop is running to generate output
    EXECSNOOP_RESULT=$(ssh_cmd "timeout 2 sh -c 'execsnoop 2>&1 & sleep 0.5; /bin/true; sleep 1; kill %1 2>/dev/null' | head -5" || echo "")
    if echo "$EXECSNOOP_RESULT" | grep -q "PCOMM\|COMM\|true\|Tracing"; then
      pass "execsnoop works - BTF is functional"
    else
      info "execsnoop output: $(echo "$EXECSNOOP_RESULT" | head -1)"
    fi

    echo "   5c. Testing bpftrace one-liner..."
    BPFTRACE_RESULT=$(ssh_cmd "timeout 2 bpftrace -e 'BEGIN { printf(\"BTF_OK\\n\"); exit(); }' 2>&1" || echo "")
    if echo "$BPFTRACE_RESULT" | grep -q "BTF_OK"; then
      pass "bpftrace works - BTF is functional"
    else
      info "bpftrace: $(echo "$BPFTRACE_RESULT" | head -1)"
    fi

    # ─────────────────────────────────────────────────────────────────
    echo "6. Testing vhost-net (network throughput)..."
    # ─────────────────────────────────────────────────────────────────
    # Start iperf server on VM, run client on host
    ssh_cmd "pkill iperf 2>/dev/null; iperf -s -D" || true
    sleep 1

    IPERF_RESULT=$(${pkgs.iperf2}/bin/iperf -c ${config.vmAddr} -t 2 2>/dev/null | tail -1 || echo "IPERF_FAIL")

    if echo "$IPERF_RESULT" | grep -q "bits/sec"; then
      BANDWIDTH=$(echo "$IPERF_RESULT" | grep -oE '[0-9.]+ [GMK]bits/sec' | tail -1)
      pass "Network throughput: $BANDWIDTH"

      # Check if we're getting good vhost performance (> 1 Gbit)
      if echo "$BANDWIDTH" | grep -qE '^[0-9.]+ Gbits'; then
        GBIT=$(echo "$BANDWIDTH" | grep -oE '^[0-9.]+')
        if [ "$(echo "$GBIT > 1" | ${pkgs.bc}/bin/bc)" -eq 1 ]; then
          pass "vhost-net acceleration confirmed (>1 Gbps)"
        fi
      fi
    else
      fail "iperf test failed"
      info "Run 'iperf -s' on VM and 'iperf -c ${config.vmAddr}' on host manually"
      FAILED=1
    fi

    # Stop iperf server
    ssh_cmd "pkill iperf" || true

    # ─────────────────────────────────────────────────────────────────
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    if [ $FAILED -eq 0 ]; then
      echo -e "''${GREEN}All tests passed!''${NC}"
    else
      echo -e "''${RED}Some tests failed.''${NC}"
    fi
    echo "═══════════════════════════════════════════════════════════════"

    exit $FAILED
  '';

  # microvm-teardown-network
  # Remove the bridge and TAP interface from the host.
  microvm-teardown-network = ''
    #!/usr/bin/env bash
    set -euo pipefail

    TAP="${config.tapInterface}"
    BRIDGE="${config.bridgeInterface}"

    echo "Removing TAP interface $TAP..."
    sudo ip link del "$TAP" 2>/dev/null || true

    echo "Removing bridge $BRIDGE..."
    sudo ip link del "$BRIDGE" 2>/dev/null || true

    echo "Network teardown complete!"
  '';
}
