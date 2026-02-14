# examples/microvms-host/nested-vms.nix
#
# Configuration for nested MicroVMs.
# Creates one MicroVM for each supported hypervisor.

{
  self,
  hypervisors,
  networkConfig,
}:

builtins.listToAttrs (
  map (hypervisor: {
    name = hypervisor;
    value = {
      config =
        { lib, ... }:
        {
          system.stateVersion = lib.trivial.release;
          networking.hostName = "${hypervisor}-microvm";

          # ════════════════════════════════════════════════════════════════
          # MicroVM Configuration
          # ════════════════════════════════════════════════════════════════
          microvm = {
            inherit hypervisor;
            interfaces = [
              {
                type = "tap";
                # Truncate long hypervisor names for interface ID
                id = "vm-${builtins.substring 0 12 hypervisor}";
                mac = networkConfig.macAddrs.${hypervisor};
              }
            ];
          };

          # ════════════════════════════════════════════════════════════════
          # Network (DHCP from host bridge)
          # ════════════════════════════════════════════════════════════════
          systemd.network.enable = true;
          # Uses default 99-ethernet-default-dhcp.network

          # ════════════════════════════════════════════════════════════════
          # SSH Access
          # ════════════════════════════════════════════════════════════════
          users.users.root.password = "toor";
          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "yes";
          };
        };
    };
  }) hypervisors
)
