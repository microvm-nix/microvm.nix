{ pkgs
, microvmConfig
, withDriveLetters
, ...
}:

let
  inherit (pkgs) lib;
  inherit (vmHostPackages.stdenv.hostPlatform) system;
  inherit (microvmConfig) vmHostPackages;

  vfkitPkg = microvmConfig.vfkit.package;

  inherit (microvmConfig)
    vcpu mem user interfaces shares socket
    storeOnDisk kernel initrdPath kernelParams
    balloon devices credentialFiles vsock graphics;

  inherit (microvmConfig.vfkit) extraArgs logLevel rosetta;

  volumesWithLetters = withDriveLetters microvmConfig;

  # vfkit requires uncompressed kernel
  kernelPath = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";

  kernelConsole = if graphics.enable then "tty0" else "hvc0";

  kernelCmdLine = [ "console=${kernelConsole}" "reboot=t" "panic=-1" ] ++ kernelParams;

  bootloaderArgs = [
    "--bootloader"
    "linux,kernel=${kernelPath},initrd=${initrdPath},cmdline=\"${builtins.concatStringsSep " " kernelCmdLine}\""
  ];

  deviceArgs =
    [
      "--device" "virtio-rng"
    ]
    ++ (if graphics.enable then [
      "--device" "virtio-gpu"
      "--device" "virtio-input,keyboard"
      "--device" "virtio-input,pointing"
    ] else [
      "--device" "virtio-serial,stdio"
    ])
    ++ (builtins.concatMap ({ image, ... }: [
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
        throw "vfkit does not support ${type} networking on macOS. Use type = \"user\" for NAT networking."
    ) interfaces)
    ++ lib.optionals rosetta.enable (
      let
        rosettaArgs = builtins.concatStringsSep "," (
          [ "rosetta" "mountTag=rosetta" ]
          ++ lib.optional rosetta.install "install"
          ++ lib.optional rosetta.ignoreIfMissing "ignoreIfMissing"
        );
      in
      [ "--device" rosettaArgs ]
    );

  allArgsWithoutSocket = [
    "${lib.getExe vfkitPkg}"
    "--cpus" (toString vcpu)
    "--memory" (toString mem)
  ]
  ++ lib.optionals (logLevel != null) [
    "--log-level" logLevel
  ]
  ++ lib.optionals graphics.enable [
    "--gui"
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
    else if rosetta.enable && !vmHostPackages.stdenv.hostPlatform.isAarch64
    then throw "Rosetta requires Apple Silicon (aarch64-darwin). Current host: ${system}"
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
      echo '{"state": "Stop"}' | ${lib.getExe vmHostPackages.socat} - "UNIX-CONNECT:$SOCKET_ABS"
    ''
    else throw "Cannot shutdown without socket";

  supportsNotifySocket = false;

  requiresMacvtapAsFds = false;
}
