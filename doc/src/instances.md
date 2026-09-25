# Instances of a shared runner

Creating a MicroVM normally means evaluating and building its NixOS
configuration. When many MicroVMs run the same system and differ only
in size, network and identity, they can share one runner instead: a new
*instance* is created in seconds, without a build.

Enable it in the shared configuration (qemu only):

```nix
microvm = {
  hypervisor = "qemu";
  instance.enable = true;
  # optional, for `microvm -s`
  vsock.ssh.enable = true;
};
```

Create the first MicroVM from it as usual, then more instances that
link to the same runner:

```bash
microvm -f git+https://... -c web1
microvm -c web2 -i web1
```

`microvm -u web2` rebuilds from the flake and configuration web2 was
created from (stored in `/var/lib/microvms/web2/{flake,config}`). An
instance of a MicroVM that is declared in the host configuration
(`microvm.vms`) has no flake reference and cannot be updated with
`microvm -u`.

## Instance values

At every start, the runner reads the following files from `instance/`
in the MicroVM's state directory. Each is optional; a missing file keeps
the value from the shared configuration. Invalid values stop the start
with a message in the `microvm@` journal. Memory of exactly 2048 MB is
rejected with qemu's `microvm` machine, which
[hangs](https://github.com/microvm-nix/microvm.nix/issues/171) with it.

| File | Content | Example |
|------|---------|---------|
| `mem` | Memory in MB | `4096` |
| `vcpu` | Number of vCPUs | `2` |
| `interfaces` | One tap interface per line: `<id> <mac>` | `vm-web2 02:00:00:00:00:02` |
| `vsock-cid` | VSOCK CID | `4202` |
| `credentials/<name>` | A [systemd credential](https://systemd.io/CREDENTIALS/) passed to the guest (name up to 28 characters) | `credentials/system.hostname` |

The tap interfaces are created by `microvm-tap-interfaces@.service` as
for any MicroVM, multi-queue when the instance has more than one vCPU;
attach them to a bridge on the host as described in
[A simple network setup](./simple-network.md).

Identity comes in through systemd credentials, for example
`system.hostname` and `system.machine_id`, or your own credentials read
by guest services with `ImportCredential=`. With `instance.enable`, the
guest has no fixed `/etc/hostname` and no fixed machine-id, so that
these apply. Make credential files readable
only by the `microvm` user.

```bash
cd /var/lib/microvms/web2/instance
echo 4096 > mem
echo 2 > vcpu
echo "vm-web2 02:00:00:00:00:02" > interfaces
mkdir -p credentials
echo -n web2 > credentials/system.hostname
chown -R microvm:kvm .
systemctl start microvm@web2
```

All instances boot the same system and share its store; each keeps its
own volumes, because relative volume paths resolve in each MicroVM's
state directory.

Tap and macvtap `interfaces` and `vsock.cid` cannot be set in a shared
configuration, and `registerWithMachined` is not supported yet.
