{ self, nixpkgs, system, ... }:

let
  vmName = "instance-a";
  sshKeys = import (nixpkgs + "/nixos/tests/ssh-keys.nix") nixpkgs.legacyPackages.${system};
in
{
  # Two MicroVMs share one runner (microvm.instance.enable); each gets its
  # own memory, vCPUs, tap interface, VSOCK CID and hostname at start.
  instances =
    import (nixpkgs + "/nixos/tests/make-test-python.nix")
      (
        { pkgs, lib, ... }:
        {
          name = "instances";
          nodes.host = {
            imports = [ self.nixosModules.host ];
            systemd.enableStrictShellChecks = true;

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
            virtualisation.memorySize = 3072;
            virtualisation.cores = 2;

            microvm.vms.${vmName} = {
              autostart = false;
              config = {
                microvm = {
                  hypervisor = "qemu";
                  instance.enable = true;
                  vsock.ssh.enable = true;
                  # a share makes qemu size a memory backend from each instance's memory
                  shares = [ {
                    proto = "virtiofs";
                    tag = "shared";
                    source = "/var/lib/instances-shared";
                    mountPoint = "/mnt/shared";
                  } ];
                };
                networking.hostName = "instance";
                users.users.root.openssh.authorizedKeys.keys = [ sshKeys.snakeOilPublicKey ];
                system.stateVersion = lib.trivial.release;
              };
            };
          };
          testScript = ''
            host.wait_for_unit("multi-user.target")
            host.succeed(
              "install -D -m 600 ${sshKeys.snakeOilPrivateKey} /root/.ssh/id_ed25519",
              "mkdir -p /var/lib/instances-shared && echo hello > /var/lib/instances-shared/file",
              # A second MicroVM on the first one's runner: no build
              "microvm -c instance-b -i ${vmName}",
              "test $(readlink /var/lib/microvms/instance-b/current) = $(readlink /var/lib/microvms/${vmName}/current)",
            )

            def run(name, command):
                # microvm -s announces the connection on stdout first
                import re
                out = re.sub(r"\x1b\[[0-9;]*m", "", host.succeed(f"microvm -s {name} {command} < /dev/null"))
                result = "\n".join(l for l in out.splitlines() if not l.startswith("Connecting to")).strip()
                return result

            def machine_id(name):
                import hashlib
                return hashlib.md5(name.encode()).hexdigest()

            def setup(name, mem, vcpu, cid, mac):
                d = f"/var/lib/microvms/{name}/instance"
                host.succeed(
                    f"mkdir -p {d}/credentials",
                    f"echo {mem} > {d}/mem",
                    f"echo {vcpu} > {d}/vcpu",
                    f"echo {cid} > {d}/vsock-cid",
                    f"echo 'vm-{name[-1]} {mac}' > {d}/interfaces",
                    f"echo -n {name} > {d}/credentials/system.hostname",
                    f"echo -n {machine_id(name)} > {d}/credentials/system.machine_id",
                    f"chown -R microvm:kvm /var/lib/microvms/{name}",
                )

            setup("${vmName}", 512, 1, 4201, "02:00:00:00:00:0a")
            setup("instance-b", 768, 2, 4202, "02:00:00:00:00:0b")
            host.succeed("systemctl start microvm@${vmName}.service microvm@instance-b.service")

            for name, mem, vcpu, mac in [("${vmName}", 512, 1, "02:00:00:00:00:0a"), ("instance-b", 768, 2, "02:00:00:00:00:0b")]:
                host.wait_until_succeeds(f"microvm -s {name} true < /dev/null", timeout=900)
                assert run(name, "hostname") == name, run(name, "hostname")
                assert run(name, "cat /etc/machine-id") == machine_id(name)
                assert run(name, "nproc") == str(vcpu)
                total = int(run(name, "grep MemTotal /proc/meminfo").split()[1]) // 1024
                assert mem - 100 < total <= mem, f"{name}: {total} MiB"
                assert mac in run(name, "'cat /sys/class/net/*/address'").split()
                assert run(name, "cat /mnt/shared/file") == "hello"
                host.succeed(f"ip link show vm-{name[-1]}")

            # Invalid instance values stop the start with a clear message
            host.succeed(
              "microvm -c instance-c -i ${vmName}",
              "echo two > /var/lib/microvms/instance-c/instance/vcpu",
              "chown -R microvm:kvm /var/lib/microvms/instance-c",
            )
            host.execute("systemctl start microvm@instance-c.service")
            host.wait_until_succeeds("journalctl -u microvm@instance-c.service | grep -F 'invalid instance/vcpu'", timeout=60)
            host.succeed("systemctl stop microvm@instance-c.service")

            host.succeed("systemctl stop microvm@instance-b.service")
            # the tap unit stops right after the MicroVM
            host.wait_until_fails("ip link show vm-b", timeout=60)
          '';
          meta.timeout = 1800;
        }
      )
      {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      };
}
