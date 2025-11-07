# Using Rosetta with vfkit on Apple Silicon

Rosetta support enables running x86_64 (Intel) binaries in your ARM64 Linux VM on Apple Silicon Macs. This is useful for running legacy applications or development tools that haven't been ported to ARM yet.

## Requirements

- Apple Silicon (M1/M2/M3/etc.) Mac
- macOS with Rosetta installed
- vfkit hypervisor

## Configuration

Enable Rosetta in your MicroVM configuration:

```nix
{
  microvm = {
    hypervisor = "vfkit";

    vfkit.rosetta = {
      enable = true;
      # Optional: install Rosetta automatically if missing
      install = true;
    };
  };
}
```

## Guest Setup

After enabling Rosetta, you need to mount the share and configure binfmt in your guest:

```nix
{
  # Mount the Rosetta share
  fileSystems."/mnt/rosetta" = {
    device = "rosetta";
    fsType = "virtiofs";
  };

  # Configure binfmt to use Rosetta for x86_64 binaries
  boot.binfmt.registrations.rosetta = {
    interpreter = "/mnt/rosetta/rosetta";
    magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
    mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
  };
}
```

## Testing

Once configured, you can verify Rosetta is working:

```bash
# Inside the VM
uname -m
# Should show: aarch64

# Try running an x86_64 binary (if you have one)
file /path/to/x86_64/binary
# Should show: ELF 64-bit LSB executable, x86-64

/path/to/x86_64/binary
# Should run successfully via Rosetta
```

## Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `microvm.vfkit.rosetta.enable` | bool | `false` | Enable Rosetta support |
| `microvm.vfkit.rosetta.mountTag` | string | `"rosetta"` | Mount tag for the virtiofs share |
| `microvm.vfkit.rosetta.install` | bool | `false` | Auto-install Rosetta if missing |
| `microvm.vfkit.rosetta.ignoreIfMissing` | bool | `false` | Continue if Rosetta unavailable |

## Limitations

- Only works on Apple Silicon Macs (M-series chips)
- vfkit will fail to start on Intel Macs if Rosetta is enabled
- Performance is slower than native ARM64 execution
- Not all x86_64 binaries may work perfectly
