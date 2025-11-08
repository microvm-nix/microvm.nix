{
  description = "Contain NixOS in a MicroVM";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    spectrum = {
      url = "git+https://spectrum-os.org/git/spectrum";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, spectrum }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
      flake-utils.lib.eachSystem systems (system: {

        apps =
          let
            pkgs = nixpkgs.legacyPackages.${system};
            nixosToApp = configFile: {
              type = "app";
              program = "${(import configFile {
                inherit self nixpkgs system;
              }).config.microvm.declaredRunner}/bin/microvm-run";
            };
          in {
            vm = nixosToApp ./examples/microvms-host.nix;
            qemu-vnc = nixosToApp ./examples/qemu-vnc.nix;
            graphics = {
              type = "app";
              program = toString (pkgs.writeShellScript "run-graphics" ''
                set -e

                if [ -z "$*" ]; then
                  echo "Usage: $0 [--tap tap0] <pkgs...>"
                  exit 1
                fi

                if [ "$1" = "--tap" ]; then
                  TAP_INTERFACE="\"$2\""
                  shift 2
                else
                  TAP_INTERFACE=null
                fi

                ${pkgs.nix}/bin/nix run \
                  -f ${./examples/graphics.nix} \
                  config.microvm.declaredRunner \
                  --arg self 'builtins.getFlake "${self}"' \
                  --arg system '"${system}"' \
                  --arg nixpkgs 'builtins.getFlake "${nixpkgs}"' \
                  --arg packages "\"$*\"" \
                  --arg tapInterface "$TAP_INTERFACE"
              '');
            };
            # Run this on your host to accept Wayland connections
            # on AF_VSOCK.
            waypipe-client = {
              type = "app";
              program = toString (pkgs.writeShellScript "waypipe-client" ''
                exec ${pkgs.waypipe}/bin/waypipe --vsock -s 6000 client
              '');
            };
          };

        packages =
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ self.overlay ];
            };

            inherit (pkgs) lib;
          in {
            build-microvm = pkgs.callPackage ./pkgs/build-microvm.nix { inherit self; };
            doc = pkgs.callPackage ./pkgs/doc.nix { };
            microvm = import ./pkgs/microvm-command.nix {
              pkgs = import nixpkgs { inherit system; };
            };
            # all compilation-heavy packages that shall be prebuilt for a binary cache
            prebuilt = pkgs.buildEnv {
              name = "prebuilt";
              paths = with self.packages.${system}; with pkgs; [
                qemu-example
                cloud-hypervisor-example
                firecracker-example
                crosvm-example
                kvmtool-example
                stratovirt-example
                # alioth-example
                virtiofsd
              ];
              pathsToLink = [ "/" ];
              extraOutputsToInstall = [ "dev" ];
              ignoreCollisions = true;
            };
          } //
          # wrap self.nixosConfigurations in executable packages
          lib.listToAttrs (
            lib.concatMap (configName:
              let
                config = self.nixosConfigurations.${configName};
                packageName = lib.replaceString "${system}-" "" configName;
                # Check if this config's guest system matches our current build system
                # (accounting for darwin hosts building linux guests)
                guestSystem = config.pkgs.stdenv.hostPlatform.system;
                buildSystem = lib.replaceString "-darwin" "-linux" system;
              in
              lib.optional (guestSystem == buildSystem)
              {
                name = packageName;
                value = config.config.microvm.runner.${config.config.microvm.hypervisor};
              }
            ) (builtins.attrNames self.nixosConfigurations)
          );

        # Takes too much memory in `nix flake show`
        # checks = import ./checks { inherit self nixpkgs system; };

        # hydraJobs are checks
        hydraJobs = builtins.mapAttrs (_: check:
          (nixpkgs.lib.recursiveUpdate check {
            meta.timeout = 12 * 60 * 60;
          })
        ) (import ./checks { inherit self nixpkgs system; });
      }) // {
        lib = import ./lib { inherit (nixpkgs) lib; };

        overlay = final: super: {
          cloud-hypervisor-graphics = import "${spectrum}/pkgs/cloud-hypervisor" { inherit final super; };
        };
        overlays.default = self.overlay;

        nixosModules = {
          microvm = ./nixos-modules/microvm;
          host = ./nixos-modules/host;
          # Just the generic microvm options
          microvm-options = ./nixos-modules/microvm/options.nix;
        };

        defaultTemplate = self.templates.microvm;
        templates.microvm = {
          path = ./flake-template;
          description = "Flake with MicroVMs";
        };

        nixosConfigurations =
          let
            inherit (nixpkgs) lib;

            hypervisorsWith9p = [
              "qemu"
              # currently broken:
              # "crosvm"
            ];
            hypervisorsWithUserNet = [ "qemu" "kvmtool" "vfkit" ];
            hypervisorsDarwinOnly = [ "vfkit" ];
            hypervisorsWithTap = builtins.filter
              # vfkit supports networking, but does not support tap
              (hv: hv != "vfkit")
              self.lib.hypervisorsWithNetwork;

            isDarwinOnly = hypervisor: builtins.elem hypervisor hypervisorsDarwinOnly;
            isDarwinSystem = system: lib.hasSuffix "-darwin" system;
            hypervisorSupportsSystem = hypervisor: system:
              # Darwin-only hypervisors only work on darwin, others work everywhere
              !(isDarwinOnly hypervisor && !(isDarwinSystem system));

            makeExample = { system, hypervisor, config ? {} }:
              lib.nixosSystem {
                system = lib.replaceString "-darwin" "-linux" system;

                modules = [
                  self.nixosModules.microvm
                  ({ lib, ... }: {
                    system.stateVersion = lib.trivial.release;

                    networking.hostName = "${hypervisor}-microvm";
                    services.getty.autologinUser = "root";

                    nixpkgs.overlays = [ self.overlay ];
                    microvm = {
                      inherit hypervisor;
                      # share the host's /nix/store if the hypervisor supports it
                      shares =
                        if builtins.elem hypervisor hypervisorsWith9p then [{
                          tag = "ro-store";
                          source = "/nix/store";
                          mountPoint = "/nix/.ro-store";
                          proto = "9p";
                        }]
                        else if hypervisor == "vfkit" then [{
                          tag = "ro-store";
                          source = "/nix/store";
                          mountPoint = "/nix/.ro-store";
                          proto = "virtiofs";
                        }]
                        else [];
                      # writableStoreOverlay = "/nix/.rw-store";
                      # volumes = [ {
                      #   image = "nix-store-overlay.img";
                      #   mountPoint = config.microvm.writableStoreOverlay;
                      #   size = 2048;
                      # } ];
                      interfaces = lib.optional (builtins.elem hypervisor hypervisorsWithUserNet) {
                        type = "user";
                        id = "qemu";
                        mac = "02:00:00:01:01:01";
                      };
                      forwardPorts = lib.optional (hypervisor == "qemu") {
                        host.port = 2222;
                        guest.port = 22;
                      };
                      # Allow build on Darwin
                      vmHostPackages = lib.mkIf (lib.hasSuffix "-darwin" system)
                        nixpkgs.legacyPackages.${system};
                    };
                    networking.firewall.allowedTCPPorts = lib.optional (hypervisor == "qemu") 22;
                    services.openssh = lib.optionalAttrs (hypervisor == "qemu") {
                      enable = true;
                      settings.PermitRootLogin = "yes";
                    };
                  })
                  config
                ];
              };

            basicExamples = lib.flatten (
              lib.map (system:
                lib.map (hypervisor: {
                  name = "${system}-${hypervisor}-example";
                  value = makeExample { inherit system hypervisor; };
                  shouldInclude = hypervisorSupportsSystem hypervisor system;
                }) self.lib.hypervisors
              ) systems
            );

            tapExamples = lib.flatten (
              lib.map (system:
                lib.imap1 (idx: hypervisor: {
                  name = "${system}-${hypervisor}-example-with-tap";
                  value = makeExample {
                    inherit system hypervisor;
                    config = _: {
                      microvm.interfaces = [ {
                        type = "tap";
                        id = "vm-${builtins.substring 0 4 hypervisor}";
                        mac = "02:00:00:01:01:0${toString idx}";
                      } ];
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
                  shouldInclude = builtins.elem hypervisor hypervisorsWithTap
                    && hypervisorSupportsSystem hypervisor system;
                }) self.lib.hypervisors
              ) systems
            );

            included = builtins.filter (ex: ex.shouldInclude) (basicExamples ++ tapExamples);
          in
            builtins.listToAttrs (builtins.map ({ name, value, ... }: { inherit name value; }) included);
      };
}
