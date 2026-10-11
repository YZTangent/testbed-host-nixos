{ pkgs, ... }:

{
  # Docker Engine
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    # Set generous ulimits for large model tensor loading into GPU memory
    extraOptions = "--default-ulimit memlock=-1:-1 --default-ulimit nofile=65536:65536";
  };

  # NVIDIA Container Toolkit (CDI): Enables GPU pass-through inside Docker containers
  # Matches Step 7 & 8 of the guide: docker run --rm --gpus all ...
  hardware.nvidia-container-toolkit.enable = true;

  # Additional container tooling
  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}
