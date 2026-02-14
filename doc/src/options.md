# Configuration options

By including the `microvm` module a set of NixOS options is made
available for customization. These are the most important ones:

| Option                         | Purpose                                                                                             |
|--------------------------------|-----------------------------------------------------------------------------------------------------|
| `microvm.hypervisor`           | Hypervisor to use by default in `microvm.declaredRunner`                                            |
| `microvm.vcpu`                 | Number of Virtual CPU cores                                                                         |
| `microvm.mem`                  | RAM allocation in MB                                                                                |
| `microvm.interfaces`           | Network interfaces                                                                                  |
| `microvm.volumes`              | Block device images                                                                                 |
| `microvm.shares`               | Shared filesystem directories                                                                       |
| `microvm.devices`              | PCI/USB devices for host-to-vm passthrough                                                          |
| `microvm.socket`               | Control socket for the Hypervisor so that a MicroVM can be shutdown cleanly                         |
| `microvm.user`                 | (qemu only) User account which Qemu will switch to when started as root                             |
| `microvm.forwardPorts`         | (qemu user-networking only) TCP/UDP port forwarding                                                 |
| `microvm.vfkit.extraArgs`      | (vfkit only) Extra arguments to pass to vfkit                                                       |
| `microvm.vfkit.logLevel`       | (vfkit only) Log level: "debug", "info", or "error" (default: "info")                               |
| `microvm.vfkit.rosetta.enable` | (vfkit only) Enable Rosetta for running x86_64 binaries on ARM64 (Apple Silicon only)               |
| `microvm.kernelBtf`            | Enable BTF (BPF Type Format) for eBPF observability tools (see below)                               |
| `microvm.kernelParams`         | Like `boot.kernelParams` but will not end up in `system.build.toplevel`, saving you rebuilds        |
| `microvm.storeOnDisk`          | Enables the store on the boot squashfs even in the presence of a share with the host's `/nix/store` |
| `microvm.writableStoreOverlay` | Optional string of the path where all writes to `/nix/store` should go to.                          |

See [the options declarations](
https://github.com/microvm-nix/microvm.nix/blob/main/nixos-modules/microvm/options.nix)
for a full reference.

## BTF (BPF Type Format) Support

Enable `microvm.kernelBtf = true` to compile BTF debug information into the
MicroVM's kernel. This is required for modern eBPF observability tools.

### Why BTF is needed

eBPF programs need to understand kernel data structures (process info, network
packets, file descriptors, etc.) to attach to kernel functions. Traditionally,
this required:

- Kernel headers matching the exact kernel version
- Recompiling eBPF programs for each kernel
- Large BCC dependencies

BTF solves this by embedding compact type information directly in the kernel.
Tools can read structure layouts at runtime, enabling **CO-RE (Compile Once,
Run Everywhere)** - a single eBPF program works across kernel versions.

### Included tools

With BTF enabled, these tools work out of the box:

| Tool | Description |
|------|-------------|
| `tcptop` | Show TCP send/receive throughput by connection |
| `execsnoop` | Trace process executions in real-time |
| `opensnoop` | Trace file opens |
| `bpftrace` | High-level eBPF tracing language |

### Example usage

```nix
{
  microvm.kernelBtf = true;

  environment.systemPackages = with pkgs; [
    bcc        # BPF Compiler Collection
    bpftrace   # High-level tracing language
  ];
}
```

See the [btf-vhost example](https://github.com/microvm-nix/microvm.nix/tree/main/examples/btf-vhost)
for a complete configuration with vhost networking and automated tests.
