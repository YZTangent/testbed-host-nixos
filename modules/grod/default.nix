{ config, pkgs, ... }:

let
  grodFhs = pkgs.buildFHSEnv {
    name = "grod";
    targetPkgs = pkgs: with pkgs; [
      # Core toolchain & CLI utilities used by flywheel-cli and lerobot
      python312
      uv
      gcc
      gnumake
      binutils
      pkg-config
      cmake
      ninja
      git
      curl
      wget
      ffmpeg
      docker

      # Exact host NVIDIA driver package (provides nvidia-smi, libcuda.so, libnvidia-ml.so
      # matching the running R570+ kernel module to prevent driver/library version mismatch)
      config.hardware.nvidia.package
      cudaPackages.cudatoolkit
      nvtopPackages.nvidia

      # C/Linux headers & shared libs required by evdev, pynput, av, and PyTorch wheels
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
    ];

    runScript = pkgs.writeShellScript "grod-init" ''
      set -euo pipefail
      export CPATH="/usr/include:''${CPATH:-}"
      export C_INCLUDE_PATH="/usr/include:''${C_INCLUDE_PATH:-}"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:/usr/lib:/usr/lib64:''${LD_LIBRARY_PATH:-}"
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
  };
in
{
  environment.systemPackages = [ grodFhs ];
}
