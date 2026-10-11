# Custom installer ISO with bleeding-edge kernel, Wi-Fi 7 firmware, and nouveau blacklisted.
# Build command:
#   nix build .#nixosConfigurations.installer-iso.config.system.build.isoImage
{ lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # Bleeding-edge kernel so MediaTek MT7902/MT7921/MT7925 and Realtek NICs are recognized
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Include all proprietary firmware
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.linux-firmware ];

  # CRITICAL: Blacklist nouveau to avoid black screen hang on RTX 5090 Blackwell during boot
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelParams = [ "nomodeset" ];

  # USB tethering modules pre-loaded
  boot.kernelModules = [
    "rndis_host"
    "cdc_ether"
    "cdc_ncm"
  ];

  # NetworkManager for convenient wifi-menu or nmcli during installation
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # Useful utilities on the live media
  environment.systemPackages = with pkgs; [
    git
    pciutils
    usbutils
    neovim
    htop
    curl
  ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
