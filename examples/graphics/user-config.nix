# examples/graphics/user-config.nix
#
# User account configuration for the graphical MicroVM.

{
  # Username for the desktop session
  username = "user";

  # User account attributes
  userAttrs = {
    password = "";
    group = "user";
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
    ];
  };

  # Passwordless sudo for convenience
  sudoConfig = {
    enable = true;
    wheelNeedsPassword = false;
  };
}
