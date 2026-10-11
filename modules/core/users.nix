{ pkgs, ... }:

let
  sharedGroups = [ "networkmanager" "docker" "video" ];
in
{
  # Allow members of 'wheel' to run sudo
  security.sudo.wheelNeedsPassword = true;

  users.mutableUsers = true;

  # Multi-user isolation for team members
  users.users = {
    # Primary administrator
    tanyuanzheng = {
      isNormalUser = true;
      description = "Yuanzheng Tan";
      extraGroups = [ "wheel" ] ++ sharedGroups;
      shell = pkgs.bashInteractive;
    };

    # Robotics / Inference Team Members
    jiehao = {
      isNormalUser = true;
      description = "Jie Hao Kong";
      extraGroups = sharedGroups;
      shell = pkgs.bashInteractive;
    };

    zhin = {
      isNormalUser = true;
      description = "Zhi An Ng";
      extraGroups = sharedGroups;
      shell = pkgs.bashInteractive;
    };

    danielkun = {
      isNormalUser = true;
      description = "Daniel Kurniadi";
      extraGroups = sharedGroups;
      shell = pkgs.bashInteractive;
    };
  };
}
