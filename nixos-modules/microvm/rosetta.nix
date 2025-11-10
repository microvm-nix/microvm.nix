{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.vfkit.rosetta;
in
lib.mkIf (config.microvm.hypervisor == "vfkit" && cfg.enable) {
  # Mount the Rosetta share
  fileSystems.${cfg.mountPoint} = {
    device = cfg.mountTag;
    fsType = "virtiofs";
  };

  # Configure binfmt to use Rosetta for x86_64 binaries
  boot.binfmt.registrations.rosetta = {
    interpreter = "${cfg.mountPoint}/rosetta";
    magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
    mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
  };
}
