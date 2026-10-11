{ pkgs, ... }:

{
  # Enable X11/Wayland display server
  services.xserver = {
    enable = true;
    displayManager.gdm = {
      enable = true;
      wayland = true;
    };
    desktopManager.gnome.enable = true;
  };

  # PipeWire audio stack
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Exclude unnecessary GNOME bloat
  environment.gnome.excludePackages = (with pkgs; [
    gnome-tour
    epiphany
    geary
  ]);
}
