{ pkgs, ... }:

{
  # Enable Firefox system-wide for all workstation users
  programs.firefox.enable = true;

  # Additional desktop / user applications
  environment.systemPackages = with pkgs; [
    wl-clipboard
  ];
}
