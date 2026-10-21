{ pkgs, ... }:

{
  # Allow proprietary packages (NVIDIA drivers, CUDA, etc.)
  nixpkgs.config.allowUnfree = true;

  # Nix daemon settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # Weekly garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Base system utilities and hardware monitoring
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    tree
    jq
    tmux
    ripgrep
    fd
    zoxide

    # GPU and hardware monitoring
    nvtopPackages.nvidia
    pciutils
    usbutils
    lm_sensors
    htop
  ];
}
