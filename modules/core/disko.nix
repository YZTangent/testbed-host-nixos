{ config, lib, ... }:

{
  options.prata.diskDevice = lib.mkOption {
    type = lib.types.str;
    default = "/dev/nvme0n1";
    description = "Primary block device formatted by disko for the testbed OS.";
  };

  config = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = config.prata.diskDevice;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1024M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "fmask=0077" "dmask=0077" ];
                  extraArgs = [ "-n" "boot" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  extraArgs = [ "-L" "nixos" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
