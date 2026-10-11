{ pkgs, ... }:

{
  home.stateVersion = "24.11";

  # User packages
  home.packages = with pkgs; [
    bat
    eza
    fd
  ];

  # Bash configuration and convenient shortcuts for GROD inference workflow
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -lah";
      nvwatch = "watch -n 1 nvidia-smi";
      safari-env = "source ~/.venv/safari/bin/activate";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
    };
  };
}
