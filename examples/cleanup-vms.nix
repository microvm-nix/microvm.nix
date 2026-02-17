# examples/cleanup-vms.nix
#
# Clean up stale MicroVM processes before running tests.
#
# Usage:
#   nix run .#cleanup-vms

{ pkgs }:

pkgs.writeShellApplication {
  name = "cleanup-vms";

  runtimeInputs = with pkgs; [
    procps
    netcat
    coreutils
  ];

  text = ''
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    echo -e "''${YELLOW}Cleaning up stale MicroVM processes...''${NC}"

    KILLED=0

    # Kill QEMU processes (match microvm pattern)
    if pkill -f "qemu-system.*microvm@" 2>/dev/null; then
      echo -e "  ''${GREEN}✓ Killed QEMU processes''${NC}"
      KILLED=$((KILLED + 1))
    fi

    # Kill cloud-hypervisor processes
    if pkill -f "cloud-hypervisor" 2>/dev/null; then
      echo -e "  ''${GREEN}✓ Killed cloud-hypervisor processes''${NC}"
      KILLED=$((KILLED + 1))
    fi

    # Kill firecracker processes
    if pkill -f "firecracker" 2>/dev/null; then
      echo -e "  ''${GREEN}✓ Killed firecracker processes''${NC}"
      KILLED=$((KILLED + 1))
    fi

    # Wait for processes to exit and ports to be released
    if [ $KILLED -gt 0 ]; then
      echo -e "  ''${YELLOW}• Waiting for ports to be released...''${NC}"
      sleep 2
    else
      echo -e "  ''${GREEN}• No stale VM processes found''${NC}"
    fi

    # Check if example ports are now free
    PORTS_FREE=true
    for port in 4321 4322 4440 4441 4480 4500 5900 5901; do
      if nc -z localhost "$port" 2>/dev/null; then
        echo -e "  ''${RED}✗ Port $port still in use''${NC}"
        PORTS_FREE=false
      fi
    done

    if [ "$PORTS_FREE" = true ]; then
      echo -e "''${GREEN}All example ports are available.''${NC}"
    else
      echo -e "''${YELLOW}Some ports still in use. They may be in TIME_WAIT state.''${NC}"
      echo -e "''${YELLOW}Wait a few seconds or use: nix run .#test-all-examples -- --skip-preflight''${NC}"
    fi
  '';
}
