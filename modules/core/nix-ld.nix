{ config, pkgs, ... }:

{
  # Enable nix-ld to seamlessly run unmodified pip-installed wheels, PyTorch CUDA 12.8,
  # and safari-sdk/flywheel-cli binaries inside Python virtual environments.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glibc
    openssl
    libGL
    glib
    cudaPackages.cudatoolkit
    config.hardware.nvidia.package
    ffmpeg
    curl
    util-linux
  ];
}
