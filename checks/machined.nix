{ self, nixpkgs, system, hypervisor }:

let
  vmName = "machined-test";
  vsockCid = 4242;
in
{
  # Test that MicroVMs can be registered with systemd-machined
  "machined-${hypervisor}" =
    import (nixpkgs + "/nixos/tests/make-test-python.nix")
      (
        { pkgs, lib, ... }:
        {
          name = "machined-${hypervisor}";
          nodes.host = {
            imports = [ self.nixosModules.host ];
            systemd.enableStrictShellChecks = true;

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

            # Define a VM with machined registration enabled
            microvm.vms.${vmName}.config = {
              microvm = {
                inherit hypervisor;
                # Enable machined registration on the VM
                registerWithMachined = true;
              }
              // lib.optionalAttrs (hypervisor != "cloud-hypervisor") {
                vsock.cid = vsockCid;
              };
              networking.hostName = vmName;
              system.stateVersion = lib.trivial.release;
            };
          };
          testScript = ''
            # Wait for the MicroVM service to start
            host.wait_for_unit("microvm@${vmName}.service", timeout = 60)
            # ^ this is actually none blocking

            # Verify the VM is registered with machined
            host.wait_until_succeeds("machinectl list | grep -q '${vmName}'", timeout=240)

            # Verify machine status works
            host.succeed("machinectl status '${vmName}'")

            # Verify the machine class is 'vm'
            host.succeed("machinectl show '${vmName}' --property=Class | grep -q 'vm'")

            ${lib.optionalString ((lib.versionAtLeast pkgs.systemd.version "259") && hypervisor != "cloud-hypervisor") ''
              # On systemd >=259 RegisterMachineEx path should expose VSOCK/SSH metadata
              host.succeed("machinectl show '${vmName}' --property=VSockCID | grep -q 'VSockCID=${toString vsockCid}'")
              host.succeed("machinectl show '${vmName}' --property=SSHAddress | grep -q 'SSHAddress=vsock/${toString vsockCid}'")
            ''}

            # Terminate the VM via machinectl (sends SIGTERM to hypervisor)
            host.succeed("machinectl terminate '${vmName}'")

            # Wait for the service to stop
            host.wait_until_fails("machinectl status '${vmName}'", timeout = 30)
          '';
          meta.timeout = 600;
        }
      )
      {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      };
}
