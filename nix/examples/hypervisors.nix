# Hypervisor capability definitions
{ lib }:

let
  inherit (import ../../lib { inherit lib; }) hypervisors hypervisorsWithNetwork;
in
{
  # All available hypervisors
  all = hypervisors;

  # Hypervisors that support 9p filesystem sharing
  with9p = [
    "qemu"
    # currently broken:
    # "crosvm"
  ];

  # Hypervisors that support user networking (no host setup required)
  withUserNet = [
    "qemu"
    "kvmtool"
    "vfkit"
  ];

  # Hypervisors that only work on Darwin
  darwinOnly = [ "vfkit" ];

  # Hypervisors that work on Darwin (qemu via HVF, vfkit natively)
  onDarwin = [
    "qemu"
    "vfkit"
  ];

  # Hypervisors that support TAP networking
  withTap =
    builtins.filter
      # vfkit supports networking, but does not support tap
      (hv: hv != "vfkit")
      hypervisorsWithNetwork;

  # Helper functions
  isDarwinOnly = hypervisor: builtins.elem hypervisor [ "vfkit" ];
  isDarwinSystem = system: lib.hasSuffix "-darwin" system;
  supportsSystem =
    hypervisor: system:
    if lib.hasSuffix "-darwin" system then
      builtins.elem hypervisor [
        "qemu"
        "vfkit"
      ]
    else
      !(builtins.elem hypervisor [ "vfkit" ]);
}
