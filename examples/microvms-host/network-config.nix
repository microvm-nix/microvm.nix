# examples/microvms-host/network-config.nix
#
# Network configuration for nested MicroVMs.
# Generates deterministic MAC and IP addresses for each hypervisor.

{ hypervisors }:

{
  # Generate MAC addresses from hypervisor name hash
  # This ensures consistent addresses across rebuilds
  macAddrs = builtins.listToAttrs (
    map (
      hypervisor:
      let
        hash = builtins.hashString "sha256" hypervisor;
        c = off: builtins.substring off 2 hash;
        # Use x2 prefix for locally administered unicast MAC
        mac = "${builtins.substring 0 1 hash}2:${c 2}:${c 4}:${c 6}:${c 8}:${c 10}";
      in
      {
        name = hypervisor;
        value = mac;
      }
    ) hypervisors
  );

  # Generate sequential IPv4 addresses starting from 10.0.0.2
  ipv4Addrs = builtins.listToAttrs (
    builtins.genList (
      i:
      let
        hypervisor = builtins.elemAt hypervisors i;
      in
      {
        name = hypervisor;
        value = "10.0.0.${toString (2 + i)}";
      }
    ) (builtins.length hypervisors)
  );
}
