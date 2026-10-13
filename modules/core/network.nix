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
    ];
  };
}
