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

The NixOS module automatically handles mounting the Rosetta virtiofs share and configuring binfmt to use Rosetta for x86_64 binaries. No additional guest configuration is required.

## Usage

Once configured, you can run any x86_64 binary in your ARM64 VM. To verify Rosetta is working:

```nix
# Add an x86_64 package to your configuration
environment.systemPackages = with pkgs; [
  file  # to verify binary architecture
  (pkgsCross.gnu64.hello)  # x86_64 version of hello
];
```

Then in the VM:

```bash
# Verify you're running on ARM64
uname -m
# Output: aarch64

# Check the binary architecture
file $(which hello)
# Output: ELF 64-bit LSB executable, x86-64, ...

# Run the x86_64 binary via Rosetta
hello
# Output: Hello, world!
```

You can use `pkgsCross.gnu64.<package>` to cross-compile any package from nixpkgs to x86_64 and run it via Rosetta.

## Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `microvm.vfkit.rosetta.enable` | bool | `false` | Enable Rosetta support |
| `microvm.vfkit.rosetta.install` | bool | `false` | Auto-install Rosetta if missing |
| `microvm.vfkit.rosetta.ignoreIfMissing` | bool | `false` | Continue if Rosetta unavailable |

## Limitations

- Only works on Apple Silicon Macs (M-series chips)
- vfkit will fail to start on Intel Macs if Rosetta is enabled
- Performance is slower than native ARM64 execution
- Not all x86_64 binaries may work perfectly
