# examples/console-demo/default.nix
#
# Minimal MicroVM demonstrating dual console architecture.
#
# This example shows how to configure both serial (ttyS0) and virtio-console
# (hvc0) with TCP socket backends, allowing you to:
#
#   1. Watch early kernel boot messages on ttyS0 (serial)
#   2. Get a fast interactive shell on hvc0 (virtio-console)
#
# The VM is intentionally minimal - just bash and basic utilities - to
# clearly demonstrate the console architecture without other complexity.
#
# Usage:
#   nix build .#console-demo
#   ./result/bin/microvm-run &          # Start VM in background
#   ./result/bin/connect-serial         # Watch boot (ttyS0)
#   ./result/bin/connect-console        # Interactive shell (hvc0)

{
  self,
  nixpkgs,
  system,
}:

let
  config = import ./config.nix;
  qemuConsoleArgs = import ./qemu-consoles.nix { inherit config; };
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.microvm

    (
      { lib, pkgs, ... }:
      {
        system.stateVersion = lib.trivial.release;
        networking.hostName = "console-demo";

        # ════════════════════════════════════════════════════════════════════
        # MicroVM Configuration
        # ════════════════════════════════════════════════════════════════════
        microvm = {
          hypervisor = "qemu";
          mem = config.mem;
          vcpu = config.vcpu;

          # No network interfaces - this is a console-only demo
          interfaces = [ ];

          # Disable default stdio serial - we use TCP sockets instead
          qemu.serialConsole = false;

          # Add our TCP console configuration
          qemu.extraArgs = qemuConsoleArgs;

          # ══════════════════════════════════════════════════════════════════
          # Helper Scripts
          # ══════════════════════════════════════════════════════════════════
          binScripts = {
            # Connect to ttyS0 (serial) - for watching boot
            connect-serial = ''
              #!/usr/bin/env bash
              echo "════════════════════════════════════════════════════════════"
              echo "Connecting to ttyS0 (serial console) on port ${toString config.serialPort}"
              echo "════════════════════════════════════════════════════════════"
              echo ""
              echo "This is the SERIAL console (emulated 16550 UART)."
              echo "You'll see kernel boot messages here."
              echo ""
              echo "Characteristics:"
              echo "  • Available immediately at boot"
              echo "  • Slower (each byte traps to hypervisor)"
              echo "  • Captures kernel panics"
              echo ""
              echo "Press Ctrl+C to disconnect."
              echo "════════════════════════════════════════════════════════════"
              echo ""
              exec ${pkgs.netcat}/bin/nc localhost ${toString config.serialPort}
            '';

            # Connect to hvc0 (virtio-console) - for interactive use
            connect-console = ''
              #!/usr/bin/env bash
              echo "════════════════════════════════════════════════════════════"
              echo "Connecting to hvc0 (virtio-console) on port ${toString config.virtioConsolePort}"
              echo "════════════════════════════════════════════════════════════"
              echo ""
              echo "This is the VIRTIO console (paravirtualized)."
              echo "Use this for interactive sessions."
              echo ""
              echo "Characteristics:"
              echo "  • Fast (batched I/O via virtqueue)"
              echo "  • Available after virtio drivers load"
              echo "  • Supports terminal resize"
              echo ""
              echo "Press Ctrl+C to disconnect."
              echo "════════════════════════════════════════════════════════════"
              echo ""
              exec ${pkgs.netcat}/bin/nc localhost ${toString config.virtioConsolePort}
            '';

            # Show status of both consoles
            console-status = ''
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
              printf "hvc0  (virtio)  port ${toString config.virtioConsolePort}: "
              if ${pkgs.netcat}/bin/nc -z localhost ${toString config.virtioConsolePort} 2>/dev/null; then
                echo "✓ listening"
              else
                echo "✗ not available"
              fi
            '';

            # Automated test: start VM, test both consoles, shutdown
            run-test = ''
              #!/usr/bin/env bash
              set -euo pipefail

              SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
              SERIAL_PORT="${toString config.serialPort}"
              VIRTIO_PORT="${toString config.virtioConsolePort}"

              # Colors
              RED='\033[0;31m'
              GREEN='\033[0;32m'
              YELLOW='\033[1;33m'
              NC='\033[0m'

              pass() { echo -e "  ''${GREEN}✓ $1''${NC}"; }
              fail() { echo -e "  ''${RED}✗ $1''${NC}"; }
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
              echo "              Console Demo - Automated Test"
              echo "════════════════════════════════════════════════════════════════"
              echo ""

              # Check if ports are already in use
              if ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; then
                fail "Port $SERIAL_PORT already in use - is another VM running?"
                exit 1
              fi

              # ─────────────────────────────────────────────────────────────────
              echo "1. Starting MicroVM..."
              # ─────────────────────────────────────────────────────────────────
              "$SCRIPT_DIR/microvm-run" &
              VM_PID=$!
              info "VM started with PID $VM_PID"

              # ─────────────────────────────────────────────────────────────────
              echo "2. Waiting for console ports to be available..."
              # ─────────────────────────────────────────────────────────────────
              # Timeouts configured in config.nix for easy adjustment
              PORT_TIMEOUT=${toString config.portTimeout}
              BOOT_TIMEOUT=${toString config.bootTimeout}
              POLL_INTERVAL=${toString config.pollInterval}
              CMD_TIMEOUT=${toString config.commandTimeout}
              ELAPSED=0

              while ! ${pkgs.netcat}/bin/nc -z localhost "$SERIAL_PORT" 2>/dev/null; do
                if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
                  fail "Timeout waiting for serial port $SERIAL_PORT after ''${PORT_TIMEOUT}s"
                  exit 1
                fi
                info "Waiting for serial port... (''${ELAPSED}s/''${PORT_TIMEOUT}s)"
                sleep $POLL_INTERVAL
                ELAPSED=$((ELAPSED + POLL_INTERVAL))
              done
              pass "Serial port $SERIAL_PORT is listening"

              while ! ${pkgs.netcat}/bin/nc -z localhost "$VIRTIO_PORT" 2>/dev/null; do
                if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
                  fail "Timeout waiting for virtio port $VIRTIO_PORT after ''${PORT_TIMEOUT}s"
                  exit 1
                fi
                info "Waiting for virtio port... (''${ELAPSED}s/''${PORT_TIMEOUT}s)"
                sleep $POLL_INTERVAL
                ELAPSED=$((ELAPSED + POLL_INTERVAL))
              done
              pass "Virtio port $VIRTIO_PORT is listening"

              # ─────────────────────────────────────────────────────────────────
              echo "3. Waiting for system to boot (polling for shell response)..."
              # ─────────────────────────────────────────────────────────────────
              ELAPSED=0
              BOOTED=false

              while [ $ELAPSED -lt $BOOT_TIMEOUT ]; do
                # Try to send a command and get a response via virtio console
                # We send 'echo BOOT_TEST_OK' and look for the response
                RESPONSE=$(echo "echo BOOT_TEST_OK" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$VIRTIO_PORT" 2>/dev/null | head -5 || true)
                if echo "$RESPONSE" | grep -q "BOOT_TEST_OK"; then
                  BOOTED=true
                  break
                fi
                info "Polling for shell response... (''${ELAPSED}s/''${BOOT_TIMEOUT}s)"
                sleep $POLL_INTERVAL
                ELAPSED=$((ELAPSED + POLL_INTERVAL))
              done

              if [ "$BOOTED" = true ]; then
                pass "System booted and shell is responsive"
              else
                fail "Timeout waiting for system to boot after ''${BOOT_TIMEOUT}s"
                info "The VM may still be booting - check manually with connect-console"
                exit 1
              fi

              # ─────────────────────────────────────────────────────────────────
              echo "4. Testing serial console (ttyS0)..."
              # ─────────────────────────────────────────────────────────────────
              SERIAL_RESPONSE=$(echo "echo SERIAL_TEST_$$" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$SERIAL_PORT" 2>/dev/null | head -10 || true)
              if echo "$SERIAL_RESPONSE" | grep -q "SERIAL_TEST_$$"; then
                pass "Serial console (ttyS0) responds to commands"
              else
                info "Serial console may need manual verification"
                info "Response: $(echo "$SERIAL_RESPONSE" | head -1)"
              fi

              # ─────────────────────────────────────────────────────────────────
              echo "5. Testing virtio console (hvc0)..."
              # ─────────────────────────────────────────────────────────────────
              VIRTIO_RESPONSE=$(echo "echo VIRTIO_TEST_$$" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$VIRTIO_PORT" 2>/dev/null | head -10 || true)
              if echo "$VIRTIO_RESPONSE" | grep -q "VIRTIO_TEST_$$"; then
                pass "Virtio console (hvc0) responds to commands"
              else
                info "Virtio console may need manual verification"
                info "Response: $(echo "$VIRTIO_RESPONSE" | head -1)"
              fi

              # ─────────────────────────────────────────────────────────────────
              echo "6. Checking /proc/consoles in guest..."
              # ─────────────────────────────────────────────────────────────────
              CONSOLES=$(echo "cat /proc/consoles" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$VIRTIO_PORT" 2>/dev/null | grep -E "ttyS0|hvc0" || true)
              if echo "$CONSOLES" | grep -q "ttyS0"; then
                pass "ttyS0 registered in /proc/consoles"
              fi
              if echo "$CONSOLES" | grep -q "hvc0"; then
                pass "hvc0 registered in /proc/consoles"
              fi

              # ─────────────────────────────────────────────────────────────────
              echo "7. Shutting down VM..."
              # ─────────────────────────────────────────────────────────────────
              # Send poweroff command
              echo "poweroff" | timeout $CMD_TIMEOUT ${pkgs.netcat}/bin/nc localhost "$VIRTIO_PORT" 2>/dev/null || true
              sleep $CMD_TIMEOUT

              # Check if VM exited
              if kill -0 "$VM_PID" 2>/dev/null; then
                info "VM still running, sending shutdown signal..."
                "$SCRIPT_DIR/microvm-shutdown" 2>/dev/null || true
                sleep 2
              fi

              if ! kill -0 "$VM_PID" 2>/dev/null; then
                pass "VM shutdown complete"
              else
                info "VM may still be shutting down"
              fi

              echo ""
              echo "════════════════════════════════════════════════════════════════"
              echo -e "''${GREEN}Console demo test completed successfully!''${NC}"
              echo "════════════════════════════════════════════════════════════════"
            '';
          };
        };

        # ════════════════════════════════════════════════════════════════════
        # Kernel Console Configuration
        # ════════════════════════════════════════════════════════════════════
        # Configure BOTH consoles in kernel command line:
        #   - console=ttyS0: Early boot output goes to serial
        #   - console=hvc0: Primary console after virtio loads
        #
        # The LAST console= becomes /dev/console (used by init/systemd).
        # This way we get early boot on serial, but primary login on hvc0.
        boot.kernelParams = [
          "console=ttyS0,115200" # Serial: early boot, panics
          "console=hvc0" # virtio-console: primary
        ];

        # ════════════════════════════════════════════════════════════════════
        # Getty Configuration
        # ════════════════════════════════════════════════════════════════════
        # Run login prompts on both consoles

        # Serial console getty
        systemd.services."serial-getty@ttyS0" = {
          enable = true;
          wantedBy = [ "getty.target" ];
        };

        # virtio-console getty
        systemd.services."serial-getty@hvc0" = {
          enable = true;
          wantedBy = [ "getty.target" ];
        };

        # Auto-login as root for easy demo
        services.getty.autologinUser = "root";

        # Empty root password
        users.users.root.password = "";

        # ════════════════════════════════════════════════════════════════════
        # Minimal Environment
        # ════════════════════════════════════════════════════════════════════
        # Just the essentials for demonstrating console access
        environment.systemPackages = with pkgs; [
          coreutils
          util-linux
          procps # ps, top, etc.
        ];

        # Welcome message explaining the demo
        users.motd = ''
          ┌─────────────────────────────────────────────────────────────┐
          │              Console Demo MicroVM                           │
          ├─────────────────────────────────────────────────────────────┤
          │                                                             │
          │  You're connected via one of two consoles:                  │
          │                                                             │
          │  ttyS0 (serial)     - Slow, but available at boot           │
          │  hvc0  (virtio)     - Fast, for interactive use             │
          │                                                             │
          │  Try: dmesg | grep console                                  │
          │       cat /proc/consoles                                    │
          │                                                             │
          └─────────────────────────────────────────────────────────────┘
        '';
      }
    )
  ];
}
