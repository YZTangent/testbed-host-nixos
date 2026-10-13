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

    # Python 3.12 + uv stack
    python312
    uv

    # Global 'grod' pull-up command available from anywhere on the filesystem
    (writeShellScriptBin "grod" ''
      set -euo pipefail
      VENV_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/grod-venv"

      if [ "''${1:-}" = "--rebuild" ]; then
        echo "==> Removing existing GROD environment at $VENV_DIR..."
        rm -rf "$VENV_DIR"
        shift
      fi

      if [ ! -d "$VENV_DIR" ]; then
        echo "==> Bootstrapping GROD Python 3.12 environment with uv at $VENV_DIR..."
        mkdir -p "$(dirname "$VENV_DIR")"
        ${pkgs.uv}/bin/uv venv "$VENV_DIR" --python ${pkgs.python312}/bin/python3.12
        source "$VENV_DIR/bin/activate"
        echo "==> Installing PyTorch CUDA 12.8 (Blackwell sm_120)..."
        ${pkgs.uv}/bin/uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
        echo "==> Installing Safari SDK & LeRobot..."
        ${pkgs.uv}/bin/uv pip install safari-sdk "git+https://github.com/huggingface/lerobot.git" absl-py datasets "lerobot[dataset]"
      else
        source "$VENV_DIR/bin/activate"
      fi

      if [ $# -gt 0 ]; then
        exec "$@"
      else
        echo "==> GROD environment active [$(pwd)] (venv: $VENV_DIR). Type 'exit' to leave."
        exec ${pkgs.bashInteractive}/bin/bash
      fi
    '')

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
