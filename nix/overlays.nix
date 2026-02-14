# Flake overlay definitions
{ spectrum }:

{
  default = final: super: {
    cloud-hypervisor-graphics = import "${spectrum}/pkgs/cloud-hypervisor" { inherit final super; };
  };
}
