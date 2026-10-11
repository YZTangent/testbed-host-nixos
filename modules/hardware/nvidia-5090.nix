{ config, lib, pkgs, ... }:

{
  # Explicitly blacklist nouveau to prevent installer/boot hang and black screen
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Load NVIDIA driver in X11/Wayland and early KMS
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required for Wayland and proper display resolution
    modesetting.enable = true;

    # Power management to prevent sleep/wake lockups on RTX 5090
    powerManagement.enable = true;
    powerManagement.finegrained = false; # Full desktop card, keep active

    # Open GPU kernel modules: REQUIRED for Blackwell (RTX 5090 / GB202) on R570+
    open = true;

    # Ensure driver version >= 570
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  # Graphics / OpenGL (CUDA & Vulkan runtime)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vaapiVdpau
      libvdpau-va-gl
      nvidia-vaapi-driver
    ];
  };

  # Wayland & Explicit Sync environment variables for NVIDIA 570+
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };
}
