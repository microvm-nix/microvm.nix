# NixOS configurations for example MicroVMs
{
  self,
  nixpkgs,
  lib,
  systems,
}:

let
  hypervisors = import ./hypervisors.nix { inherit lib; };

  makeExample =
    {
      system,
      hypervisor,
      config ? { },
    }:
    lib.nixosSystem {
      system = lib.replaceString "-darwin" "-linux" system;

      modules = [
        self.nixosModules.microvm
        (
          { lib, ... }:
          {
            system.stateVersion = lib.trivial.release;

            networking.hostName = "${hypervisor}-microvm";
            services.getty.autologinUser = "root";

            nixpkgs.overlays = [ self.overlay ];
            microvm = {
              inherit hypervisor;
              # share the host's /nix/store if the hypervisor supports it
              shares =
                if builtins.elem hypervisor hypervisors.with9p then
                  [
                    {
                      tag = "ro-store";
                      source = "/nix/store";
                      mountPoint = "/nix/.ro-store";
                      proto = "9p";
                    }
                  ]
                else if hypervisor == "vfkit" then
                  [
                    {
                      tag = "ro-store";
                      source = "/nix/store";
                      mountPoint = "/nix/.ro-store";
                      proto = "virtiofs";
                    }
                  ]
                else
                  [ ];
              # writableStoreOverlay = "/nix/.rw-store";
              # volumes = [ {
              #   image = "nix-store-overlay.img";
              #   mountPoint = config.microvm.writableStoreOverlay;
              #   size = 2048;
              # } ];
              interfaces = lib.optional (builtins.elem hypervisor hypervisors.withUserNet) {
                type = "user";
                id = "qemu";
                mac = "02:00:00:01:01:01";
              };
              forwardPorts = lib.optional (hypervisor == "qemu") {
                host.port = 2222;
                guest.port = 22;
              };
              # Allow build on Darwin
              vmHostPackages = lib.mkIf (lib.hasSuffix "-darwin" system) nixpkgs.legacyPackages.${system};
            };
            networking.firewall.allowedTCPPorts = lib.optional (hypervisor == "qemu") 22;
            services.openssh = lib.optionalAttrs (hypervisor == "qemu") {
              enable = true;
              settings.PermitRootLogin = "yes";
            };
          }
        )
        config
      ];
    };

  basicExamples = lib.flatten (
    lib.map (
      system:
      lib.map (hypervisor: {
        name = "${system}-${hypervisor}-example";
        value = makeExample { inherit system hypervisor; };
        shouldInclude = hypervisors.supportsSystem hypervisor system;
      }) hypervisors.all
    ) systems
  );

  tapExamples = lib.flatten (
    lib.map (
      system:
      lib.imap1 (idx: hypervisor: {
        name = "${system}-${hypervisor}-example-with-tap";
        value = makeExample {
          inherit system hypervisor;
          config = _: {
            microvm.interfaces = [
              {
                type = "tap";
                id = "vm-${builtins.substring 0 4 hypervisor}";
                mac = "02:00:00:01:01:0${toString idx}";
              }
            ];
            networking = {
              interfaces.eth0.useDHCP = true;
              firewall.allowedTCPPorts = [ 22 ];
            };
            services.openssh = {
              enable = true;
              settings.PermitRootLogin = "yes";
            };
          };
        };
        shouldInclude =
          builtins.elem hypervisor hypervisors.withTap && hypervisors.supportsSystem hypervisor system;
      }) hypervisors.all
    ) systems
  );

  included = builtins.filter (ex: ex.shouldInclude) (basicExamples ++ tapExamples);
in
builtins.listToAttrs (
  builtins.map (
    { name, value, ... }:
    {
      inherit name value;
    }
  ) included
)
