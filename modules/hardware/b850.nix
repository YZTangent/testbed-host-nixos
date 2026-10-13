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
    "mt7921e" # Driver for MT7902 (14c3:7902) & MT7921/MT7922
    "mt7925e" # Driver for MT7925/MT7927
    "btusb"   # MT7902 Bluetooth component
    "btmtk"   # MediaTek Bluetooth firmware loader
    "kvm-amd"
    "rndis_host"
    "cdc_ether"
    "cdc_ncm"
  ];

  # MediaTek MT7902 (PCI ID 14c3:7902): Dynamically register device ID to mt7921e driver
  # if not already built into the kernel's static PCI ID table.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x14c3", ATTR{device}=="0x7902", RUN+="${pkgs.kmod}/bin/modprobe mt7921e", RUN+="${pkgs.bash}/bin/sh -c 'echo 14c3 7902 > /sys/bus/pci/drivers/mt7921e/new_id 2>/dev/null || true'"
  '';
}
