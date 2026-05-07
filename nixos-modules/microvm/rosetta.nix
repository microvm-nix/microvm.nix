{ config, lib, ... }:

lib.mkIf (config.microvm.hypervisor == "vfkit" && config.microvm.vfkit.rosetta.enable) {
  virtualisation.rosetta.enable = true;
}
