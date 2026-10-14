{ config, pkgs, ... }:

let
  grodFhs = pkgs.buildFHSEnv {
    name = "grod";
    targetPkgs = pkgs: with pkgs; [
      # Core toolchain & CLI utilities
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
      cacert

      # Exact host NVIDIA driver package & CUDA runtime
      config.hardware.nvidia.package
      cudaPackages.cudatoolkit
      nvtopPackages.nvidia

      # Kernel, USB, Serial & Camera hardware libs (lerobot, v4l2, evdev, pyserial)
      linuxHeaders
      glibc
      glibc.dev
      systemd # libudev.so.1
      libevdev
      libusb1
      libusb1.dev
      v4l-utils
      hidapi

      # Core C/C++, Compression, Crypto & Database shared libs (PEP 600 manylinux, pyarrow, datasets)
      stdenv.cc.cc
      stdenv.cc.cc.lib
      zlib
      zlib.dev
      bzip2
      xz
      zstd
      lz4
      snappy
      openssl
      openssl.dev
      libffi
      libffi.dev
      sqlite
      expat
      ncurses
      readline
      util-linux
      libxml2
      libxslt

      # Vision, Audio, OpenGL, Vulkan & Windowing (opencv, torchvision, rerun-sdk, mujoco)
      libGL
      libGLU
      mesa
      vulkan-loader
      glfw
      glib
      alsa-lib
      libpulseaudio
      fontconfig
      freetype
      dbus
      pango
      cairo
      gdk-pixbuf
      gtk3
      libjpeg
      libpng
      libtiff
      libwebp

      # X11 & Wayland (pynput, opencv, matplotlib, rerun-sdk, mujoco)
      wayland
      libxkbcommon
      libx11
      libx11.dev
      libxext
      libxi
      libxtst
      libxrender
      libxfixes
      libxcursor
      libxrandr
      libxinerama
      libxcb
      libSM
      libICE
    ];

    runScript = pkgs.writeShellScript "grod-init" ''
      set -euo pipefail
      export CPATH="/usr/include:''${CPATH:-}"
      export C_INCLUDE_PATH="/usr/include:''${C_INCLUDE_PATH:-}"
      export CPLUS_INCLUDE_PATH="/usr/include:''${CPLUS_INCLUDE_PATH:-}"
      export LIBRARY_PATH="/usr/lib:/usr/lib64:''${LIBRARY_PATH:-}"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:/usr/lib:/usr/lib64:''${LD_LIBRARY_PATH:-}"

      # Ensure OpenSSL, Python requests, and Safari SDK gRPC/BoringSSL find system CA roots
      export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
      export REQUESTS_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
      export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="/etc/ssl/certs/ca-certificates.crt"

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
