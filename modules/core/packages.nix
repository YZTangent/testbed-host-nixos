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

    # Global 'grod' FHS environment command available from anywhere on the filesystem.
    # Uses buildFHSEnv so C extensions like 'evdev' find /usr/include/linux/input.h natively.
    (buildFHSEnv {
      name = "grod";
      targetPkgs = pkgs: with pkgs; [
        python312
        uv
        gcc
        gnumake
        binutils
        pkg-config
        cmake
        ninja
        git
        ffmpeg

        # C/Linux headers & libs required by evdev, pynput, av, and PyTorch wheels
        linuxHeaders
        glibc.dev
        libevdev
        stdenv.cc.cc.lib
        zlib
        zlib.dev
        openssl
        openssl.dev
        libGL
        glib
        libx11
        libx11.dev
        libxext
        libxi
        libxtst
        cudaPackages.cudatoolkit
        linuxPackages.nvidia_x11
      ];
      runScript = writeShellScript "grod-init" ''
        set -euo pipefail
        export CPATH="/usr/include:''${CPATH:-}"
        export C_INCLUDE_PATH="/usr/include:''${C_INCLUDE_PATH:-}"
        VENV_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/grod-venv"

        if [ "''${1:-}" = "--rebuild" ]; then
          echo "==> Removing existing GROD environment at $VENV_DIR..."
          rm -rf "$VENV_DIR"
          shift
        fi

        if [ ! -f "$VENV_DIR/.bootstrapped" ]; then
          echo "==> Bootstrapping GROD Python 3.12 FHS environment with uv at $VENV_DIR..."
          mkdir -p "$(dirname "$VENV_DIR")"
          uv venv --clear "$VENV_DIR" --python python3.12
          source "$VENV_DIR/bin/activate"
          echo "==> Installing PyTorch CUDA 12.8 (Blackwell sm_120)..."
          uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
          echo "==> Installing Safari SDK & LeRobot..."
          uv pip install safari-sdk "git+https://github.com/huggingface/lerobot.git" absl-py datasets "lerobot[dataset]"
          touch "$VENV_DIR/.bootstrapped"
        else
          source "$VENV_DIR/bin/activate"
        fi

        if [ $# -gt 0 ]; then
          exec "$@"
        else
          echo "==> GROD FHS environment active [$(pwd)] (venv: $VENV_DIR). Type 'exit' to leave."
          exec bash
        fi
      '';
    })

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
