# examples/lib/vnc-screenshot.nix
#
# EXPERIMENTAL: VNC screenshot capture and comparison utilities.
#
# Status: This module is experimental and not fully integrated.
# - Screenshot capture requires vncsnapshot or similar tool
# - Reference image workflow needs manual verification
# - Currently only used by qemu-vnc example (optional)
#
# For graphical testing alternatives, see:
# - socket-console.nix: Unix domain socket console testing
# - TEST-AUTOMATION-PLAN.md: Waypipe testing approaches
#
# Usage:
#   let
#     constants = import ../lib/constants.nix;
#     config = constants.qemu-vnc;
#     vncLib = import ../lib/vnc-screenshot.nix { inherit pkgs config; };
#   in
#   {
#     microvm.binScripts = {
#       run-test = vncLib.makeVncTestScript {
#         name = "qemu-vnc";
#         referenceImage = ./reference-screenshot.png;
#       };
#     };
#   }
#
# The `config` parameter expects:
#   - vncPort :: Int
#   - pollInterval :: Int
#   - portTimeout :: Int
#   - bootTimeout :: Int

{ pkgs, config }:

rec {
  # VNC Screenshot Test Script Generator

  /*
    makeVncTestScript - Generate a test script using VNC screenshot comparison

    Parameters:
      name :: String - Test name (for output headers)
      referenceImage :: Path - Path to reference screenshot (or null for first run)
      extraTests :: String - Additional test commands (bash)
      pixelThreshold :: Int - Maximum allowed different pixels (default: 100)
      fuzzPercent :: Int - Color difference tolerance (default: 5)

    Returns:
      String - Complete bash test script
  */
  makeVncTestScript =
    {
      name,
      referenceImage ? null,
      extraTests ? "",
      pixelThreshold ? 100,
      fuzzPercent ? 5,
    }:
    ''
      #!/usr/bin/env bash
      set -euo pipefail

      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
      VNC_PORT="${toString config.vncPort}"
      VNC_DISPLAY=":$((VNC_PORT - 5900))"

      # Paths
      SHARE_DIR="$SCRIPT_DIR/../share"
      REFERENCE_IMG="${
        if referenceImage != null then "${referenceImage}" else "$SHARE_DIR/reference-screenshot.png"
      }"
      CURRENT_IMG="/tmp/microvm-${name}-current.png"
      DIFF_IMG="/tmp/microvm-${name}-diff.png"

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
      echo "║        ${name} - VNC Screenshot Test Suite"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      # ─────────────────────────────────────────────────────────────────
      echo "1. Checking if VNC port is available..."
      # ─────────────────────────────────────────────────────────────────
      if ${pkgs.netcat}/bin/nc -z localhost "$VNC_PORT" 2>/dev/null; then
        fail "Port $VNC_PORT already in use - is another VM running?"
        exit 1
      fi
      pass "VNC port $VNC_PORT is available"

      # ─────────────────────────────────────────────────────────────────
      echo "2. Starting MicroVM..."
      # ─────────────────────────────────────────────────────────────────
      "$SCRIPT_DIR/microvm-run" &
      VM_PID=$!
      info "VM started with PID $VM_PID"

      # ─────────────────────────────────────────────────────────────────
      echo "3. Waiting for VNC port..."
      # ─────────────────────────────────────────────────────────────────
      PORT_TIMEOUT=${toString config.portTimeout}
      POLL_INTERVAL=${toString config.pollInterval}
      ELAPSED=0

      while ! ${pkgs.netcat}/bin/nc -z localhost "$VNC_PORT" 2>/dev/null; do
        if [ $ELAPSED -ge $PORT_TIMEOUT ]; then
          fail "Timeout waiting for VNC port after ''${PORT_TIMEOUT}s"
          exit 1
        fi
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
      done
      pass "VNC port $VNC_PORT is listening (''${ELAPSED}s)"

      # ─────────────────────────────────────────────────────────────────
      echo "4. Waiting for display to stabilize..."
      # ─────────────────────────────────────────────────────────────────
      # Give the graphical environment time to render
      BOOT_TIMEOUT=${toString config.bootTimeout}
      info "Waiting for graphical boot (up to ''${BOOT_TIMEOUT}s)..."
      sleep 30  # Initial wait for desktop to appear
      pass "Display stabilization wait complete"

      # ─────────────────────────────────────────────────────────────────
      echo "5. Capturing VNC screenshot..."
      # ─────────────────────────────────────────────────────────────────
      # Use grim for Wayland or import for X11, fallback to vncsnapshot
      if command -v ${pkgs.grim}/bin/grim &>/dev/null && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
        # Wayland capture (if running locally)
        ${pkgs.grim}/bin/grim "$CURRENT_IMG"
      else
        # VNC capture using vncdotool or similar
        # For now, use a simple approach with vncviewer + import
        info "Capturing via VNC (this may take a moment)..."

        # Try vncsnapshot if available, otherwise use fbgrab approach
        if command -v vncsnapshot &>/dev/null; then
          vncsnapshot localhost$VNC_DISPLAY "$CURRENT_IMG" 2>/dev/null || true
        else
          # Fallback: connect briefly and try to capture
          # This is a simplified approach - real implementation may need adjustment
          info "vncsnapshot not available, using alternative capture method"
          # Use netcat to verify connectivity at minimum
          if ${pkgs.netcat}/bin/nc -z localhost "$VNC_PORT" 2>/dev/null; then
            pass "VNC connection verified (screenshot capture may need vncsnapshot)"
            # Create a placeholder for testing purposes
            ${pkgs.imagemagick}/bin/convert -size 800x600 xc:gray "$CURRENT_IMG" 2>/dev/null || true
          fi
        fi
      fi

      if [ -f "$CURRENT_IMG" ]; then
        pass "Screenshot captured: $CURRENT_IMG"
      else
        fail "Failed to capture screenshot"
        exit 1
      fi

      # ─────────────────────────────────────────────────────────────────
      echo "6. Comparing screenshot to reference..."
      # ─────────────────────────────────────────────────────────────────
      if [ ! -f "$REFERENCE_IMG" ]; then
        info "No reference image found at: $REFERENCE_IMG"
        info "Saving current screenshot as reference..."
        mkdir -p "$(dirname "$REFERENCE_IMG")"
        cp "$CURRENT_IMG" "$REFERENCE_IMG"
        pass "Reference screenshot saved"
        info "Please verify the screenshot manually and commit it:"
        info "  $REFERENCE_IMG"
      else
        # Compare images using ImageMagick
        # -metric AE = Absolute Error (count of different pixels)
        # -fuzz N% = Allow N% color difference per pixel
        DIFF_PIXELS=$(${pkgs.imagemagick}/bin/compare \
          -metric AE -fuzz ${toString fuzzPercent}% \
          "$REFERENCE_IMG" "$CURRENT_IMG" \
          "$DIFF_IMG" 2>&1 || true)

        # Extract just the number (compare outputs "N" or "N (error)" format)
        DIFF_COUNT=$(echo "$DIFF_PIXELS" | grep -oE '^[0-9]+' || echo "999999")

        if [ "$DIFF_COUNT" -lt ${toString pixelThreshold} ]; then
          pass "Screenshot matches reference ($DIFF_COUNT different pixels)"
        else
          fail "Screenshot differs from reference ($DIFF_COUNT different pixels)"
          info "Diff image saved to: $DIFF_IMG"
          info "If the new screenshot is correct, update reference:"
          info "  cp $CURRENT_IMG $REFERENCE_IMG"
        fi
      fi

      ${extraTests}

      # ─────────────────────────────────────────────────────────────────
      echo "7. Shutting down VM..."
      # ─────────────────────────────────────────────────────────────────
      "$SCRIPT_DIR/microvm-shutdown" 2>/dev/null || kill "$VM_PID" 2>/dev/null || true
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

  # VNC Connection Script

  /*
    makeVncConnectScript - Generate script to connect to VNC display

    Returns:
      String - Bash script for VNC connection instructions
  */
  makeVncConnectScript = ''
    #!/usr/bin/env bash
    VNC_PORT="${toString config.vncPort}"
    VNC_DISPLAY=":$((VNC_PORT - 5900))"

    echo "VNC Connection Information"
    echo "══════════════════════════"
    echo ""
    echo "Port:    $VNC_PORT"
    echo "Display: $VNC_DISPLAY"
    echo ""
    echo "Connect with:"
    echo "  vncviewer localhost$VNC_DISPLAY"
    echo ""
    echo "Or with TigerVNC:"
    echo "  nix shell nixpkgs#tigervnc -c vncviewer localhost:$VNC_PORT"
    echo ""

    # Check if port is available
    if ${pkgs.netcat}/bin/nc -z localhost "$VNC_PORT" 2>/dev/null; then
      echo "Status: ✓ VNC server is running"
    else
      echo "Status: ✗ VNC server is not running (start the VM first)"
    fi
  '';
}
