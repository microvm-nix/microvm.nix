{
  description = "Contain NixOS in a MicroVM";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    spectrum = {
      url = "git+https://spectrum-os.org/git/spectrum";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      spectrum,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      overlays = import ./nix/overlays.nix { inherit spectrum; };
    in
    {
      apps = forAllSystems (system: import ./nix/apps.nix { inherit self nixpkgs system; });

      packages = forAllSystems (system: import ./nix/packages.nix { inherit self nixpkgs system; });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      # Takes too much memory in `nix flake show`
      # checks = forAllSystems (system:
      #   import ./checks { inherit self nixpkgs system; };
      # );

      # hydraJobs are checks
      hydraJobs = forAllSystems (
        system:
        builtins.mapAttrs (
          _: check:
          (nixpkgs.lib.recursiveUpdate check {
            meta.timeout = 12 * 60 * 60;
          })
        ) (import ./checks { inherit self nixpkgs system; })
      );

      lib = import ./lib { inherit (nixpkgs) lib; };

      overlay = overlays.default;
      inherit overlays;

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

      nixosConfigurations = import ./nix/examples {
        inherit self nixpkgs systems;
        inherit (nixpkgs) lib;
      };
    };
}
