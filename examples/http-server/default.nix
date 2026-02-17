# examples/http-server/default.nix
#
# Fast-starting nginx web server demonstrating:
#   - QEMU user-mode networking (no root required)
#   - Port forwarding (host 28080 -> guest 80)
#   - Boot-to-serve time measurement
#   - Dual consoles (serial + virtio)
#
# Usage:
#   nix build .#http-server
#   ./result/bin/microvm-run &
#   curl http://localhost:28080/
#   curl http://localhost:28080/health
#   curl http://localhost:28080/api/info

{
  self,
  nixpkgs,
  system,
  tapInterface ? null, # null = user-mode, "tap0" = TAP mode
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
        hostName = "http-server";
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

          # Networking: user-mode (SLIRP) or TAP
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

          # Port forwarding for user-mode networking
          forwardPorts = lib.optionals (tapInterface == null) [
            {
              from = "host";
              host.port = cfg.httpPortUser;
              guest.port = cfg.httpPortGuest;
            }
          ];

          # Disable default serial (we configure TCP sockets)
          qemu.serialConsole = false;

          # QEMU arguments: process name + consoles
          qemu.extraArgs = [
            "-name"
            "${hostName},process=${hostName}"
          ]
          ++ qemuConsoleArgs;

          # Helper scripts in result/bin/
          binScripts = scripts;
        };

        boot.kernelParams = [
          "console=ttyS0,115200" # Early boot on serial
          "console=hvc0" # Primary console (virtio) after boot
        ];

        # Getty on both consoles
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

        services.nginx = {
          enable = true;
          virtualHosts.default = {
            root = pkgs.writeTextDir "index.html" ''
              <!DOCTYPE html>
              <html>
              <head><title>MicroVM HTTP Server</title></head>
              <body>
                <h1>Hello from MicroVM!</h1>
                <p>Hostname: ${hostName}</p>
                <p>This page is served by nginx inside a MicroVM.</p>
                <p>Try: <a href="/health">/health</a> | <a href="/api/info">/api/info</a></p>
              </body>
              </html>
            '';
            locations."/health".return = "200 'OK'";
            locations."/api/info".extraConfig = ''
              default_type application/json;
              return 200 '{"hostname": "${hostName}", "time": "$time_iso8601", "server": "nginx"}';
            '';
          };
        };

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

        # Minimal packages
        environment.systemPackages = with pkgs; [
          curl # For self-testing inside VM
        ];
      }
    )
  ];
}
