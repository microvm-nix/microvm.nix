{ pkgs
, microvmConfig
, ...
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig)
    hostName preStart user
    vcpu mem balloon initialBalloonMem hotplugMem hotpluggedMem interfaces volumes shares devices vsock
    kernel initrdPath credentialFiles
    storeDisk storeOnDisk;

  muMsvm = pkgs.stdenv.mkDerivation {
    pname = "mu-msvm";
    version = "25.1.4";
    src = pkgs.fetchurl {
      url = "https://github.com/microsoft/mu_msvm/releases/download/v25.1.4/RELEASE-X64-artifacts.zip";
      hash = "0dm6cv84lhwzxva7qsdphdi1fm853lb37b0x658bdrcy82xx2gik";
    };
    
  };

in {
  preStart = ''
    ${preStart}
    export HOME=$PWD
  '';

  command =
    if user != null
    then throw "openvmm will not change user"
    else if initialBalloonMem != 0
    then throw "openvmm does not support initialBalloonMem"
    else if hotplugMem != 0
    then throw "openvmm does not support hotplugMem"
    else if hotpluggedMem != 0
    then throw "openvmm does not support hotpluggedMem"
    else if credentialFiles != {}
    then throw "openvmm does not support credentialFiles"
    else builtins.concatStringsSep " " (
      [
        "${pkgs.openvmm}/bin/openvmm"
        "--hv"
        "-m" "${toString mem}MB"
        "-p" (toString vcpu)
        "--virtio-console"
        "-k" (lib.escapeShellArg "${kernel.dev}/vmlinux")
        "-r" initrdPath
        "-c" (lib.escapeShellArg "console=hvc0 verbose reboot=k panic=1 ${toString microvmConfig.kernelParams}")
      ]
      ++
      lib.optionals storeOnDisk [
        "--disk" (lib.escapeShellArg "file:${storeDisk},ro")
      ]
      ++
      builtins.concatMap ({ serial, image, readOnly, ... }:
        lib.warnIf (serial != null) ''
          Volume serial is not supported for openvmm
        ''
        [ "--disk"
          (lib.escapeShellArg "${image}${
            lib.optionalString readOnly ",ro"
          }")
        ]
      ) volumes
      ++
      builtins.concatMap ({ proto, source, tag, readOnly, ... }:
        if proto == "9p"
        then if readOnly then
          throw "openvmm does not support readonly 9p share"
        else [
          "--virtio-9p" (lib.escapeShellArg "${source},${tag}")
        ] else throw "virtiofs shares not implemented for openvmm"
      ) shares
      ++
      builtins.concatMap ({ type, id, mac, ... }:
        if type == "tap"
        then [
          "--virtio-net" "tap"
        ]
        else throw "interface type ${type} is not supported by openvmm"
      ) interfaces
      # ++
      # map ({ bus, path }: {
      #   pci = lib.escapeShellArg "--vfio-pci=${path}";
      #   usb = throw "USB passthrough is not supported on openvmm";
      # }.${bus}) devices
      # ++
      # lib.optionals (vsock.cid != null) [
      #   "--vsock" (toString vsock.cid)
      # ]
    );

  # TODO:
  canShutdown = false;
}
