{ nixpkgs, self, system, ... }:

let
  host = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.host
      {
        networking.hostName = "host";
        microvm.vms.test.config = {
          microvm.shares = [
            {
              tag = "relative";
              source = "etc/ssh";
              mountPoint = "/home";
            }
            {
              tag = "absolute";
              source = "/srv/share";
              mountPoint = "/share";
            }
            {
              tag = "store";
              source = "/nix/store";
              mountPoint = "/nix/store";
            }
          ];
        };
      }
    ];
  };

  tmpfiles = host.config.systemd.tmpfiles.settings."10-microvm";
in
assert builtins.hasAttr "/var/lib/microvms/test/etc/ssh" tmpfiles;
assert builtins.hasAttr "/srv/share" tmpfiles;
assert builtins.hasAttr "/var/lib/microvms/test" tmpfiles;
assert !(builtins.hasAttr "/nix/store" tmpfiles);
nixpkgs.legacyPackages.${system}.runCommandLocal "microvm-relative-share-source" { } "touch $out"
