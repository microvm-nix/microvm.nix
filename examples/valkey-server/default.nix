# examples/valkey-server/default.nix
#
# High-performance Valkey (Redis-compatible) server demonstrating:
#   - Sub-second boot-to-serve time
#   - QEMU user-mode networking
#   - Built-in benchmarking
#   - Dual consoles
#
# Usage:
#   nix build .#valkey-server
#   ./result/bin/microvm-run &
#   valkey-cli -p 16379 PING
#   valkey-cli -p 16379 SET foo bar
#   valkey-cli -p 16379 GET foo

{
  self,
  nixpkgs,
  system,
  tapInterface ? null,
}:

let
  cfg = import ./config.nix;
  qemuConsoleArgs = import ./qemu-consoles.nix { config = cfg; };
  helperScripts = import ./helper-scripts.nix;
in

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.microvm

    (
      { lib, pkgs, ... }:
      let
        hostName = "valkey-server";
        scripts = helperScripts {
          inherit pkgs;
          config = cfg;
        };
      in
      {
        system.stateVersion = lib.trivial.release;
        networking.hostName = hostName;

        microvm = {
          hypervisor = "qemu";
          mem = cfg.mem;
          vcpu = cfg.vcpu;

          interfaces = [
            (
              if tapInterface == null then
                {
                  type = "user";
                  id = "usernet";
                  mac = cfg.vmMac;
                }
              else
                {
                  type = "tap";
                  id = tapInterface;
                  mac = cfg.vmMac;
                }
            )
          ];

          forwardPorts = lib.optionals (tapInterface == null) [
            {
              from = "host";
              host.port = cfg.valkeyPortUser;
              guest.port = cfg.valkeyPortGuest;
            }
          ];

          qemu.serialConsole = false;

          qemu.extraArgs = [
            "-name"
            "${hostName},process=${hostName}"
          ]
          ++ qemuConsoleArgs;

          binScripts = scripts;
        };

        boot.kernelParams = [
          "console=ttyS0,115200"
          "console=hvc0"
        ];

        # Getty services
        systemd.services."serial-getty@ttyS0" = {
          enable = true;
          wantedBy = [ "getty.target" ];
        };
        systemd.services."serial-getty@hvc0" = {
          enable = true;
          wantedBy = [ "getty.target" ];
        };
        services.getty.autologinUser = "root";
        users.users.root.password = "";

        # Valkey (using redis module with valkey package)
        services.redis.package = pkgs.valkey;
        services.redis.servers."" = {
          enable = true;
          port = cfg.valkeyPortGuest;
          bind = "0.0.0.0"; # Accept connections from host
          settings = {
            maxmemory = "256mb";
            maxmemory-policy = "allkeys-lru";
            # Disable persistence for fast startup
            save = [ ];
            # Allow external connections without password (for testing)
            protected-mode = "no";
          };
        };

        # Note: firewall is disabled below for boot performance,
        # so no firewall.allowedTCPPorts needed

        # Boot time optimizations (saves ~1s total)
        # Disable firewall - saves ~500ms, not needed for isolated VM
        networking.firewall.enable = false;

        # Disable time sync - saves ~270ms, not needed for ephemeral VMs
        services.timesyncd.enable = false;

        # Disable systemd-resolved - saves ~200ms
        # Use simple static DNS (QEMU SLIRP provides DNS at 10.0.2.3)
        services.resolved.enable = false;
        networking.nameservers = [ "10.0.2.3" ];

        # TAP mode networking
        systemd.network = lib.mkIf (tapInterface != null) {
          enable = true;
          networks."10-eth" = {
            matchConfig.Type = "ether";
            addresses = [ { Address = "${cfg.vmAddr}/24"; } ];
            routes = [ { Gateway = cfg.bridgeAddr; } ];
          };
        };

        # Include CLI tools for testing inside VM
        environment.systemPackages = with pkgs; [
          valkey # valkey-cli, valkey-benchmark
        ];
      }
    )
  ];
}
