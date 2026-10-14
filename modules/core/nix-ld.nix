{ config, pkgs, ... }:

{
  # Enable nix-ld with PEP 600 manylinux, CUDA, Robotics, and Vision shared libraries
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    glibc
    zlib
    bzip2
    xz
    zstd
    lz4
    snappy
    openssl
    libffi
    sqlite
    expat
    ncurses
    readline
    util-linux
    libxml2
    libxslt
    curl
    ffmpeg

    # Hardware, USB, Serial & Cameras
    systemd # libudev.so.1
    libevdev
    libusb1
    v4l-utils
    hidapi

    # Graphics, CUDA, Audio & Windowing
    config.hardware.nvidia.package
    cudaPackages.cudatoolkit
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
    wayland
    libxkbcommon
    libx11
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
}
