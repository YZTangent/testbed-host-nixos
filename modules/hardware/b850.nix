{ config, lib, pkgs, ... }:

{
  # Bleeding-edge Linux Kernel: Required for AM5 B850 chipset, PCIe 5.0,
  # and modern wireless/ethernet controllers.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Essential firmware for wireless devices (MediaTek MT7902/MT7921/MT7925, Realtek)
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.linux-firmware ];

  # AMD AM5 CPU optimization: Microcode and autonomous P-state
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
  boot.kernelParams = [
    "amd_pstate=active"
    "pcie_aspm=off"
  ];

  # USB tethering modules (Android / iOS) ensuring out-of-the-box internet fallback
  # for initial bring-up if MT7902 Wi-Fi lacks PCIe ID in stock firmware.
  boot.initrd.availableKernelModules = [
    "rndis_host"
    "cdc_ether"
    "cdc_ncm"
    "cdc_subset"
  ];

  boot.kernelModules = [
    "mt7921e"
    "mt7925e"
    "kvm-amd"
    "rndis_host"
    "cdc_ether"
    "cdc_ncm"
  ];
}
