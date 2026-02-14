# examples/graphics/wayland-env.nix
#
# Environment variables for Wayland session.
# These ensure applications use Wayland by default.

{
  WAYLAND_DISPLAY = "wayland-1";
  DISPLAY = ":0";

  # Qt Applications
  QT_QPA_PLATFORM = "wayland";

  # GTK Applications
  GDK_BACKEND = "wayland";

  # Electron Applications
  XDG_SESSION_TYPE = "wayland";

  # SDL Applications
  SDL_VIDEODRIVER = "wayland";

  # Clutter Applications
  CLUTTER_BACKEND = "wayland";
}
