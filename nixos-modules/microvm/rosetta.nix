{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.vfkit.rosetta;
  mountPoint = "/run/rosetta";
  mountTag = "rosetta";
in
lib.mkIf (config.microvm.hypervisor == "vfkit" && cfg.enable) {
  fileSystems.${mountPoint} = {
    device = mountTag;
    fsType = "virtiofs";
  };

  boot.binfmt.registrations.rosetta = {
    interpreter = "${mountPoint}/rosetta";
    magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
    mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
  };
}
