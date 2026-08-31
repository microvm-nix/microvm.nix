{ config, lib, pkgs, ... }:
let
  inherit (config.networking) hostName;
  crosvmLayoutEnabled =
    config.microvm.crosvm.memoryBase != null
    || config.microvm.crosvm.platformMmio != null;
  memoryEnd =
    if config.microvm.crosvm.memoryBase == null then null
    else config.microvm.crosvm.memoryBase + config.microvm.mem * 1024 * 1024;
  platformMmioEnd =
    if config.microvm.crosvm.platformMmio == null then null
    else config.microvm.crosvm.platformMmio.base + config.microvm.crosvm.platformMmio.size;
  protection = config.microvm.crosvm.protection;
  isProtected = protection.mode != "unprotected";
  usesNativeCrosvmVirtiofs =
    config.microvm.hypervisor == "crosvm"
    && config.microvm.crosvm.virtiofsBackend == "crosvm";
  virtiofsShares = builtins.filter ({ proto, ... }: proto == "virtiofs") config.microvm.shares;
  rawProtectionArgs = [
    "--protected-vm"
    "--protected-vm-with-firmware"
    "--protected-vm-without-firmware"
    "--swiotlb"
    "--unprotected-vm-with-firmware"
  ];

in
lib.mkIf config.microvm.guest.enable {
  assertions =
    # check for duplicate volume images
    map (volumes: {
      assertion = builtins.length volumes == 1;
      message = ''
        MicroVM ${hostName}: volume image "${(builtins.head volumes).image}" is used ${toString (builtins.length volumes)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ image, ... }: image) config.microvm.volumes
      )
    )
    ++
    # check for duplicate interface ids
    map (interfaces: {
      assertion = builtins.length interfaces == 1;
      message = ''
        MicroVM ${hostName}: interface id "${(builtins.head interfaces).id}" is used ${toString (builtins.length interfaces)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ id, ... }: id) config.microvm.interfaces
      )
    )
    ++
    # check for bridge interfaces
    map ({ id, type, bridge, ... }:
      if type == "bridge"
      then {
        assertion = bridge != null;
        message = ''
          MicroVM ${hostName}: interface ${id} is of type "bridge"
          but doesn't have a bridge to attach to defined.
        '';
      }
      else {
        assertion = bridge == null;
        message = ''
          MicroVM ${hostName}: interface ${id} is not of type "bridge"
          and therefore shouldn't have a "bridge" option defined.
        '';
      }
    ) config.microvm.interfaces
    ++
    # check for interface name length
    map ({ id, ... }: {
      assertion = builtins.stringLength id <= 15;
      message = ''
        MicroVM ${hostName}: interface name ${id} is longer than the
        the maximum length of 15 characters on Linux.
      '';
    }) config.microvm.interfaces
    ++
    # check for duplicate share tags
    map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${hostName}: share tag "${(builtins.head shares).tag}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ tag, ... }: tag) config.microvm.shares
      )
    )
    ++
    # check for duplicate share sockets
    map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${hostName}: share socket "${(builtins.head shares).socket}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ socket, ... }: toString socket) (
          builtins.filter ({ proto, ... }: proto == "virtiofs")
            config.microvm.shares
        )
      )
    )
    ++
    # check for virtiofs shares without socket
    map ({ tag, socket, ... }: {
      assertion = socket != null;
      message = ''
        MicroVM ${hostName}: virtiofs share with tag "${tag}" is missing a `socket` path.
      '';
    }) (
      builtins.filter ({ proto, ... }: proto == "virtiofs")
        config.microvm.shares
    )
    ++
    # check for virtiofs shares where posixAcl conflicts with translate-uid/gid
    # (--posix-acl and --translate-uid/--translate-gid are mutually exclusive in virtiofsd;
    # --translate-uid/gid can come from either per-share extraArgs or global microvm.virtiofsd.extraArgs)
    map ({ tag, posixAcl, extraArgs, ... }: {
      assertion = !(posixAcl && (
        lib.any (s: lib.hasInfix "--translate-uid" s || lib.hasInfix "--translate-gid" s)
          (config.microvm.virtiofsd.extraArgs ++ extraArgs)
      ));
      message = ''
        MicroVM ${hostName}: virtiofs share "${tag}" has posixAcl=true but
        extraArgs (per-share or global microvm.virtiofsd.extraArgs) contains
        --translate-uid/--translate-gid, which conflict with --posix-acl.
        Set posixAcl=false on this share to use UID/GID remapping.
      '';
    }) (
      builtins.filter ({ proto, ... }: proto == "virtiofs")
        config.microvm.shares
    )
    ++
    map ({ path, ... }: {
      assertion = config.microvm.hypervisor == "crosvm";
      message = ''
        MicroVM ${hostName}: platform device "${path}" is only supported with Crosvm.
      '';
    }) (builtins.filter ({ bus, ... }: bus == "platform") config.microvm.devices)
    ++
    map ({ path, crosvm, ... }: {
      assertion = crosvm.dtSymbol != null;
      message = ''
        MicroVM ${hostName}: platform device "${path}" requires `crosvm.dtSymbol`.
      '';
    }) (builtins.filter ({ bus, ... }: bus == "platform") config.microvm.devices)
    ++
    map ({ path, bus, crosvm, ... }: {
      assertion = (crosvm.mmioBase == null && !crosvm.mapEarly) || bus == "platform";
      message = ''
        MicroVM ${hostName}: Crosvm fixed/early mapping for device "${path}" is only supported on the platform bus.
      '';
    }) config.microvm.devices
    ++
    [
      {
        assertion =
          !(builtins.any ({ bus, ... }: bus == "platform") config.microvm.devices)
          || config.microvm.crosvm.deviceTreeOverlays != [];
        message = ''
          MicroVM ${hostName}: platform devices require a `microvm.crosvm.deviceTreeOverlays` entry.
        '';
      }
      {
        assertion =
          config.microvm.crosvm.deviceTreeOverlays == []
          || config.microvm.hypervisor == "crosvm";
        message = ''
          MicroVM ${hostName}: `microvm.crosvm.deviceTreeOverlays` is only supported with Crosvm.
        '';
      }
      {
        assertion =
          !crosvmLayoutEnabled
          || (
            config.microvm.hypervisor == "crosvm"
            && pkgs.stdenv.hostPlatform.system == "aarch64-linux"
          );
        message = ''
          MicroVM ${hostName}: explicit Crosvm RAM/platform MMIO layout requires AArch64 and the crosvm hypervisor.
        '';
      }
      {
        assertion =
          memoryEnd == null
          || platformMmioEnd == null
          || memoryEnd <= config.microvm.crosvm.platformMmio.base
          || platformMmioEnd <= config.microvm.crosvm.memoryBase;
        message = ''
          MicroVM ${hostName}: Crosvm RAM and platform MMIO ranges overlap.
        '';
      }
      {
        assertion = lib.all (arg: !builtins.elem arg config.microvm.crosvm.extraArgs) rawProtectionArgs;
        message = "Use `microvm.crosvm.protection` instead of raw Crosvm protection arguments.";
      }
      {
        assertion = !isProtected || config.microvm.hypervisor == "crosvm";
        message = "Protected MicroVMs require the crosvm hypervisor.";
      }
      {
        assertion = !isProtected || pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "Crosvm protected MicroVMs are currently supported only on AArch64 Linux.";
      }
      {
        assertion = protection.mode == "protected-with-firmware" || protection.firmware == null;
        message = "`microvm.crosvm.protection.firmware` requires protected-with-firmware mode.";
      }
      {
        assertion = protection.mode != "protected-with-firmware" || protection.firmware != null;
        message = "protected-with-firmware mode requires `microvm.crosvm.protection.firmware`.";
      }
      {
        assertion = isProtected || protection.swiotlbSizeMiB == null;
        message = "`microvm.crosvm.protection.swiotlbSizeMiB` requires a protected mode.";
      }
      {
        assertion = !isProtected || !config.microvm.balloon;
        message = "Crosvm protected MicroVMs do not support ballooning.";
      }
      {
        assertion =
          !isProtected
          || config.microvm.shares == [ ]
          || (
            usesNativeCrosvmVirtiofs
            && builtins.length virtiofsShares == builtins.length config.microvm.shares
          );
        message = "Crosvm protected MicroVMs support only native Crosvm virtio-fs shares.";
      }
      {
        assertion =
          config.microvm.crosvm.virtiofsBackend == "vhost-user"
          || config.microvm.hypervisor == "crosvm";
        message = "The native Crosvm virtio-fs backend requires the crosvm hypervisor.";
      }
      {
        assertion =
          !usesNativeCrosvmVirtiofs
          || lib.all ({ readOnly, ... }: !readOnly) virtiofsShares;
        message = "The native Crosvm virtio-fs backend does not support read-only shares.";
      }
      {
        assertion =
          !usesNativeCrosvmVirtiofs
          || lib.all ({ cache, ... }: cache != "metadata") virtiofsShares;
        message = "The native Crosvm virtio-fs backend does not support metadata-only caching.";
      }
      {
        assertion =
          !usesNativeCrosvmVirtiofs
          || lib.all ({ extraArgs, ... }: extraArgs == [ ]) virtiofsShares;
        message = "The native Crosvm virtio-fs backend does not accept virtiofsd arguments.";
      }
      {
        assertion = !protection.allowDeviceAssignment || isProtected;
        message = "Protected device assignment requires a protected Crosvm mode.";
      }
      {
        assertion =
          !protection.allowDeviceAssignment
          || lib.all ({ crosvm, ... }: crosvm.iommu == "pkvm-iommu") config.microvm.devices;
        message = "Protected device assignment requires `iommu = \"pkvm-iommu\"` for every assigned device.";
      }
      {
        assertion =
          !protection.allowDeviceAssignment
          || lib.all ({ bus, ... }: lib.elem bus [ "platform" "pci" ]) config.microvm.devices;
        message = "Protected device assignment supports static platform and PCI devices only.";
      }
      {
        assertion = !isProtected || config.microvm.devices == [ ] || protection.allowDeviceAssignment;
        message = "Crosvm protected MicroVM device assignment requires an explicit backend opt-in.";
      }
      {
        assertion = !isProtected || !config.microvm.graphics.enable;
        message = "Crosvm protected MicroVMs cannot use the host graphics backend.";
      }
    ]
    ++
    # blacklist forwardPorts
    [ {
      assertion =
        config.microvm.forwardPorts != [] -> (
          config.microvm.hypervisor == "qemu" &&
          builtins.any ({ type, ... }: type == "user") config.microvm.interfaces
        );
      message = ''
        MicroVM ${hostName}: `config.microvm.forwardPorts` works only with qemu and one network interface with `type = "user"`
      '';
    } ]
    ++
    # cloud-hypervisor specific asserts
    lib.optionals (config.microvm.hypervisor == "cloud-hypervisor") [ {
      assertion = ! (lib.any (str: lib.hasInfix "oem_strings" str) config.microvm.cloud-hypervisor.platformOEMStrings);
      message = ''
        MicroVM ${hostName}: `config.microvm.cloud-hypervisor.platformOEMStrings` items must not contain `oem_strings`
      '';
    } ];


  warnings =
    # 32 MB is just an optimistic guess, not based on experience
    lib.optional (config.microvm.mem < 32) ''
      MicroVM ${hostName}: ${toString config.microvm.mem} MB of RAM is uncomfortably narrow.
    ''
    ++ lib.optional config.nix.optimise.automatic ''
      Optimising the nix store is not recommended as it either uses lots of file handles with virtiofsd or as it doesn't do what you expect with a block device.
    '';
}
