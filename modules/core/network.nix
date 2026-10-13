{ ... }:

{
  networking.hostName = "grod-rtx5090";
  networking.networkmanager = {
    enable = true;
    # Disable Wi-Fi power saving: MediaTek mt7921e/mt7902 drops scans and connections when powersave is active
    wifi.powersave = false;
  };

  # Enable OpenSSH daemon for remote lab access and team collaboration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Open standard ports for SSH and GROD model server / inference endpoints
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      8000  # Default vLLM / model-server API
      8080  # WebUI / monitoring
      11434 # Ollama (if used)
      60061 # GROD model-server gRPC port (flywheel-cli serve default)
    ];
  };

  # go/bastion-exception compliance for SG-SIN-MBC2 Dual-Plane (Corp MNP eth0 + PA Lab Type 1 eth1):
  # Strictly disable IP routing/forwarding between interfaces.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  # Short-term interim remote access (Option 2): Persistent Reverse SSH Tunnel to GCP IAP Bastion VM
  # Uncomment and set user/GCE_IP until SG-SIN-MBC2 Room Tamarind (6B6012) / Block 80 PA Lab comes online:
  # services.autossh.sessions = [
  #   {
  #     name = "gcp-iap-bastion";
  #     user = "tanyuanzheng";
  #     monitoringPort = 0;
  #     extraArguments = "-N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2222:localhost:22 <GCE_BASTION_IP>";
  #   }
  # ];
}
