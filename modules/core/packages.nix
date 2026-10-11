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

  # System-wide packages fulfilling GROD guide requirements
  environment.systemPackages = with pkgs; [
    # Core build tools and dependencies from Guide Step 1
    ffmpeg
    pkg-config
    git
    gcc
    gnumake
    binutils

    # Python 3.12 stack
    python312
    python312Packages.virtualenv
    python312Packages.pip

    # GPU and hardware monitoring
    nvtopPackages.nvidia
    pciutils
    usbutils
    lm_sensors
    htop

    # Utilities
    curl
    wget
    tree
    jq
    tmux
    ripgrep
  ];
}
