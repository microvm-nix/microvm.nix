{ self, nixpkgs, system, ... }:

# The runner a declarative MicroVM booted from must survive garbage collection
# while the VM runs: microvm@ stops it through booted/bin/microvm-shutdown,
# and once a rebuild has moved `current` on, nothing else references it (#633).

let
  vmName = "booted-gcroot";
in
{
  "booted-gcroot" =
    import (nixpkgs + "/nixos/tests/make-test-python.nix")
      (
        { lib, ... }:
        {
          name = "booted-gcroot";
          nodes.host = {
            imports = [ self.nixosModules.host ];

            boot.kernelModules = [ "kvm" ];
            virtualisation.qemu.options = [
              "-cpu"
              {
                "aarch64-linux" = "cortex-a72";
                "x86_64-linux" = "kvm64,+svm,+vmx";
              }
              .${system}
            ];
            virtualisation.diskSize = 4096;

            microvm.vms.${vmName}.config = {
              microvm.hypervisor = "qemu";
              networking.hostName = vmName;
              system.stateVersion = lib.trivial.release;
            };
            # The guest need not finish an ACPI shutdown inside the test VM;
            # what matters is which ExecStop systemd could run.
            systemd.services."microvm@${vmName}".serviceConfig.TimeoutStopSec = 20;
          };
          testScript = ''
            booted = "/var/lib/microvms/${vmName}/booted"

            host.wait_for_unit("microvm@${vmName}.service", timeout = 120)
            runner = host.succeed(f"readlink {booted}").strip()

            with subtest("the booted runner is a GC root while the VM runs"):
                roots = host.succeed("nix-store --gc --print-roots")
                assert f'"{booted}" -> {runner}' in roots, roots

            with subtest("stop runs the booted runner's microvm-shutdown"):
                host.succeed(f"test -x {booted}/bin/microvm-shutdown")
                host.succeed("systemctl stop microvm@${vmName}")
                host.fail("journalctl -u microvm@${vmName} | grep -F 'Unable to locate executable'")
                host.fail("journalctl -u microvm@${vmName} | grep -F 'status=203/EXEC'")

            with subtest("a stopped VM roots nothing and leaves gc working"):
                host.succeed(f"test ! -e {booted}")
                host.succeed("nix-store --gc --max-freed 1")
          '';
          meta.timeout = 600;
        }
      )
      {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      };
}
