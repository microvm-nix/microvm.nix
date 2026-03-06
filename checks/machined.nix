{ self, nixpkgs, system, hypervisor }:

let
  pkgs = nixpkgs.legacyPackages.${system};
  vmName = "machined-test";
in
{
  # Test that MicroVMs can be registered with systemd-machined
  "machined-${hypervisor}" = pkgs.nixosTest {
    name = "machined-${hypervisor}";
    nodes.host = { lib, ... }: {
      imports = [ self.nixosModules.host ];

      virtualisation.qemu.options = [
        "-cpu"
        {
          "aarch64-linux" = "cortex-a72";
          "x86_64-linux" = "kvm64,+svm,+vmx";
        }.${system}
      ];
      virtualisation.diskSize = 4096;

      # Define a VM with machined registration enabled
      microvm.vms.${vmName}.config = {
        microvm = {
          hypervisor = hypervisor;
          # Enable machined registration on the VM
          registerWithMachined = true;
        };
        networking.hostName = vmName;
        system.stateVersion = lib.trivial.release;
      };
    };
    testScript = ''
      # Wait for the MicroVM service to start
      host.wait_for_unit("microvm@${vmName}.service", timeout = 1200)

      # Verify the VM is registered with machined
      host.succeed("machinectl list | grep -q '${vmName}'")

      # Verify machine status works
      host.succeed("machinectl status '${vmName}'")

      # Verify the machine class is 'vm'
      host.succeed("machinectl show '${vmName}' --property=Class | grep -q 'vm'")

      # Verify leader PID exists
      host.succeed("machinectl show '${vmName}' --property=Leader | grep -q '^Leader=[0-9]'")

      # Terminate the VM via machinectl (sends SIGTERM to hypervisor)
      host.succeed("machinectl terminate '${vmName}'")

      # Wait for the service to stop
      host.wait_until_fails("machinectl status '${vmName}'", timeout = 30)
    '';
    meta.timeout = 1800;
  };
}
