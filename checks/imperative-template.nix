{
  self,
  nixpkgs,
  system,
  ...
}:

{
  imperative-template = import (nixpkgs + "/nixos/tests/make-test-python.nix") (_: {
    name = "imperative-template";

    nodes.host = {
      imports = [ self.nixosModules.host ];
      systemd.enableStrictShellChecks = true;
      microvm.host.enable = true;
    };

    testScript = /* python */ ''
      host.wait_for_unit("multi-user.target")

      host.succeed("mkdir -p /var/lib/microvms/test/current/bin")
      host.succeed("""cat > /var/lib/microvms/test/current/bin/microvm-run <<'EOF'
      #!/bin/sh
      trap 'exit 0' TERM INT
      while true; do sleep 1; done
      EOF
      chmod +x /var/lib/microvms/test/current/bin/microvm-run
      """)
      host.succeed("""cat > /var/lib/microvms/test/current/bin/microvm-shutdown <<'EOF'
      #!/bin/sh
      exit 0
      EOF
      chmod +x /var/lib/microvms/test/current/bin/microvm-shutdown
      """)
      host.succeed("chown microvm:kvm -R /var/lib/microvms/")

      # Should work in imperative mode without microvm-register/microvm-unregister scripts.
      host.succeed("systemctl start microvm@test.service")
      host.wait_for_unit("microvm@test.service")

      host.succeed("systemctl stop microvm@test.service")
      host.wait_until_succeeds("! systemctl is-active --quiet microvm@test.service")
    '';

    meta.timeout = 600;
  })
  {
    inherit system;
    pkgs = nixpkgs.legacyPackages.${system};
  };
}
