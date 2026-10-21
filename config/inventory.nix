{
  prata-host = {
    hostName = "prata-host";
    profile = "prod";
    diskDevice = "/dev/nvme0n1";
    agePublicKey = null;
    swap = {
      enable = true;
      diskPercent = 20;
      maxSizeGiB = 128;
    };
  };
}
