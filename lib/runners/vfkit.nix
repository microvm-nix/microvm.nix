{ pkgs
, microvmConfig
, macvtapFds
, withDriveLetters
, ...
}:

let
  inherit (pkgs) lib;
  inherit (vmHostPackages.stdenv.hostPlatform) system;
  inherit (microvmConfig) vmHostPackages;

  vfkit = vmHostPackages.vfkit;

  inherit (microvmConfig)
    hostName vcpu mem user interfaces volumes shares socket
    storeOnDisk kernel initrdPath storeDisk kernelParams
    balloon devices credentialFiles vsock;

  inherit (microvmConfig.vfkit) extraArgs logLevel;

  volumesWithLetters = withDriveLetters microvmConfig;

  # vfkit requires uncompressed kernel
  kernelPath = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";

  kernelCmdLine = "console=hvc0 reboot=t panic=-1 ${toString kernelParams}";

  bootloaderArgs = [
    "--bootloader"
    "linux,kernel=${kernelPath},initrd=${initrdPath},cmdline=\"${builtins.concatStringsSep " " kernelCmdLine}\""
  ];

  deviceArgs =
    [ "--device" "virtio-rng" ]
    ++
    [ "--device" "virtio-serial,stdio" ]
    ++
    (builtins.concatMap ({ image, ... }: [
      "--device" "virtio-blk,path=${image}"
    ]) volumesWithLetters)
    ++ (builtins.concatMap ({ proto, source, tag, ... }:
      if proto == "virtiofs" then [
        "--device" "virtio-fs,sharedDir=${source},mountTag=${tag}"
      ]
      else
        throw "vfkit does not support ${proto} share. Use proto = \"virtiofs\" instead."
    ) shares)
    ++ (builtins.concatMap ({ type, id, mac, ... }:
      if type == "user" then [
        "--device" "virtio-net,nat,mac=${mac}"
      ]
      else if type == "bridge" then
        throw "vfkit bridge networking requires vmnet-helper which is not yet implemented. Use type = \"user\" for NAT networking."
      else
        throw "Unknown network interface type: ${type}"
    ) interfaces);

  allArgsWithoutSocket = [
    "${lib.getExe vfkit}"
    "--cpus" (toString vcpu)
    "--memory" (toString mem)
  ]
  ++ lib.optionals (logLevel != null) [
    "--log-level" logLevel
  ]
  ++ bootloaderArgs
  ++ deviceArgs
  ++ extraArgs;

in
{
  tapMultiQueue = false;

  preStart = lib.optionalString (socket != null) ''
    rm -f ${socket}
  '';

  command =
    if !vmHostPackages.stdenv.hostPlatform.isDarwin
    then throw "vfkit only works on macOS (Darwin). Current host: ${system}"
    else if vmHostPackages.stdenv.hostPlatform.isAarch64 != pkgs.stdenv.hostPlatform.isAarch64
    then throw "vfkit requires matching host and guest architectures. Host: ${system}, Guest: ${pkgs.stdenv.hostPlatform.system}"
    else if user != null
    then throw "vfkit does not support changing user"
    else if balloon
    then throw "vfkit does not support memory ballooning"
    else if devices != []
    then throw "vfkit does not support device passthrough"
    else if credentialFiles != {}
    then throw "vfkit does not support credentialFiles"
    else if vsock.cid != null
    then throw "vfkit vsock support not yet implemented in microvm.nix"
    else if storeOnDisk
    then throw "vfkit does not support storeOnDisk. Use virtiofs shares instead (already configured in examples)."
    else
      let
        baseCmd = lib.escapeShellArgs allArgsWithoutSocket;
        vfkitCmd = lib.concatStringsSep " " (map lib.escapeShellArg allArgsWithoutSocket);
      in
      # vfkit requires absolute socket paths, so expand relative paths
      if socket != null
      then "bash -c ${lib.escapeShellArg ''
        SOCKET_ABS=${lib.escapeShellArg socket}
        [[ "$SOCKET_ABS" != /* ]] && SOCKET_ABS="$PWD/$SOCKET_ABS"
        exec ${vfkitCmd} --restful-uri "unix:///$SOCKET_ABS"
      ''}"
      else baseCmd;

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
      SOCKET_ABS="${lib.escapeShellArg socket}"
      [[ "$SOCKET_ABS" != /* ]] && SOCKET_ABS="$PWD/$SOCKET_ABS"
      echo '{"state": "Stop"}' | ${vmHostPackages.socat}/bin/socat - "UNIX-CONNECT:$SOCKET_ABS"
    ''
    else throw "Cannot shutdown without socket";

  supportsNotifySocket = false;

  requiresMacvtapAsFds = false;
}
