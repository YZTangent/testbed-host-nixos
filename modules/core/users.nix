{ config, lib, pkgs, ... }:

let
  cfg = config.prata;
  sharedGroups = [ "networkmanager" "docker" "video" ];

  devUserSubmodule = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Full display name for the developer account.";
      };
      extraGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = sharedGroups;
        description = "Supplemental groups for the developer account.";
      };
    };
  };
in
{
  options.prata = {
    profile = lib.mkOption {
      type = lib.types.enum [ "prod" "dev" ];
      default = "prod";
      description = "Testbed build profile: 'prod' (prata-admin + prata only, no Home Manager) or 'dev' (adds devUsers with Home Manager).";
    };

    devUsers = lib.mkOption {
      type = lib.types.attrsOf devUserSubmodule;
      default = {
        tanyuanzheng = {
          description = "Yuanzheng Tan";
          extraGroups = [ "wheel" ] ++ sharedGroups;
        };
        jiehao = {
          description = "Jie Hao Kong";
          extraGroups = sharedGroups;
        };
        zhin = {
          description = "Zhi An Ng";
          extraGroups = sharedGroups;
        };
        danielkun = {
          description = "Daniel Kurniadi";
          extraGroups = sharedGroups;
        };
      };
      description = "Developer accounts enabled and managed with Home Manager when prata.profile == 'dev'.";
    };
  };

  config = {
    # Allow members of 'wheel' to run sudo
    security.sudo.wheelNeedsPassword = true;

    users.mutableUsers = true;

    # Base accounts (present on both prod and dev testbeds; no Home Manager)
    users.users = {
      prata-admin = {
        isNormalUser = true;
        description = "PRATA Privileged Administrator";
        extraGroups = [ "wheel" ] ++ sharedGroups;
        shell = pkgs.bashInteractive;
      };

      prata = {
        isNormalUser = true;
        description = "PRATA Operator";
        extraGroups = sharedGroups;
        shell = pkgs.bashInteractive;
      };
    } // lib.optionalAttrs (cfg.profile == "dev") (
      lib.mapAttrs (_: u: {
        isNormalUser = true;
        inherit (u) description extraGroups;
        shell = pkgs.bashInteractive;
      }) cfg.devUsers
    );

    home-manager = lib.mkIf (cfg.profile == "dev") {
      useGlobalPkgs = true;
      useUserPackages = true;
      users = lib.mapAttrs (_: _: import ../../home) cfg.devUsers;
    };
  };
}
