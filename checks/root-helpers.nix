{ self, nixpkgs, system, ... }:

# Root units of a declarative MicroVM must not run anything the VMM user
# (`microvm`) can plant: #628. The test plays a process that has escaped into
# that account. It retargets the VM's `current` link at a copy of the runner
# whose root-run hooks append to a marker in /run, which only root can write,
# then restarts the VM and checks that no hook ran.

let
  vmName = "root-helpers";
  stateDir = "/var/lib/microvms";
  hooks = [
    "tap-up"
    "macvtap-up"
    "pci-setup"
    "virtiofsd-run"
    "microvm-register"
  ];
in
{
  "root-helpers" =
    import (nixpkgs + "/nixos/tests/make-test-python.nix")
      (
        { pkgs, lib, ... }:
        let
          plantHooks = pkgs.writeShellScript "plant-hooks" ''
            set -eu
            d=${stateDir}/${vmName}
            real=$(readlink -f "$d/current")
            rm -rf "$d/planted"
            mkdir -p "$d/planted/bin"
            ln -s "$real/share" "$d/planted/share"
            for f in "$real"/bin/*; do ln -s "$f" "$d/planted/bin/"; done
            for hook in ${lib.concatStringsSep " " hooks}; do
              rm -f "$d/planted/bin/$hook"
              {
                echo '#!/bin/sh'
                echo "echo $hook >> /run/planted-hooks-ran"
                if [ -e "$real/bin/$hook" ]; then
                  echo "exec $real/bin/$hook \"\$@\""
                fi
              } > "$d/planted/bin/$hook"
              chmod 755 "$d/planted/bin/$hook"
            done
            ln -sfnT "$d/planted" "$d/current"
          '';
        in
        {
          name = "root-helpers";
          nodes.host = {
            imports = [ self.nixosModules.host ];

            boot.kernelModules = [ "kvm" ];
            virtualisation.qemu.options = [
              "-cpu"
              {
                "aarch64-linux" = "cortex-a72";
                "x86_64-linux" = "kvm64,+svm,+vmx";
              }
              .${system}
            ];
            virtualisation.diskSize = 4096;

            microvm.vms.${vmName}.config = {
              microvm = {
                hypervisor = "qemu";
                interfaces = [ {
                  type = "tap";
                  id = "vm-root-help";
                  mac = "02:00:00:00:00:01";
                } ];
                shares = [ {
                  proto = "virtiofs";
                  tag = "share";
                  source = "/var/lib/root-helpers-share";
                  mountPoint = "/share";
                } ];
              };
              networking.hostName = vmName;
              system.stateVersion = lib.trivial.release;
            };
          };
          testScript = ''
            host.wait_for_unit("microvm@${vmName}.service", timeout = 120)

            with subtest("hooks planted by the VMM user do not run as root"):
                host.succeed("systemctl stop microvm@${vmName}")
                host.succeed("setpriv --reuid=microvm --regid=kvm --clear-groups ${plantHooks}")
                host.succeed("systemctl start microvm@${vmName}")
                host.wait_for_unit("microvm@${vmName}.service", timeout = 120)
                ran = host.succeed("cat /run/planted-hooks-ran 2>/dev/null || true").strip()
                assert ran == "", "root ran planted hooks: " + ", ".join(ran.split())

            with subtest("root does not write into the VMM-writable directory"):
                host.succeed('test "$(stat -c %U:%G:%a ${stateDir})" = root:root:755')
                host.succeed("test ! -e ${stateDir}/${vmName}/supervisord.log")
                host.succeed("test -e /run/microvm-virtiofsd/${vmName}/supervisord.pid")
                host.succeed("systemctl stop microvm@${vmName}")

            with subtest("root units execute the declared runner"):
                for unit in ["microvm-tap-interfaces", "microvm-virtiofsd"]:
                    exec_start = host.succeed(f"systemctl show -p ExecStart --value {unit}@${vmName}")
                    assert "${stateDir}" not in exec_start, exec_start
                post = host.succeed("systemctl show -p ExecStartPost --value microvm@${vmName}")
                assert "${stateDir}" not in post, post
          '';
          meta.timeout = 900;
        }
      )
      {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      };
}
