{ pkgs, ... }:

{
  home.stateVersion = "26.11";

  # User packages (managed via Home Manager on dev beds)
  home.packages = with pkgs; [
    bat
    eza
  ];

  # Bash configuration and convenient shortcuts for GROD inference workflow
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -lah";
      nvwatch = "watch -n 1 nvidia-smi";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
    };
  };
}
