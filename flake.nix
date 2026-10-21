{
  description = "NixOS configuration for AMD B850 + NVIDIA RTX 5090 LLM/VLM Inference Workstation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, ... }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      inventory = import ./config/inventory.nix;

      mkTestbed = _: hostCfg:
        lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/workstation
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              networking.hostName = hostCfg.hostName;
              prata.profile = hostCfg.profile or "prod";
              prata.diskDevice = hostCfg.diskDevice or "/dev/nvme0n1";
              prata.swap = hostCfg.swap or { };
            }
          ];
        };

      inventoryConfigs = lib.mapAttrs' (
        key: hostCfg: lib.nameValuePair (hostCfg.hostName or key) (mkTestbed key hostCfg)
      ) inventory;
    in
    {
      nixosConfigurations = inventoryConfigs // {
        # Backwards-compatible alias to default prata-host
        workstation = inventoryConfigs.prata-host;

        # Custom Installer ISO with latest Linux kernel + Wi-Fi 7 firmware baked in
        installer-iso = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs self; };
          modules = [
            ./modules/installer/iso.nix
          ];
        };
      };

      packages.${system} = {
        iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
        default = self.packages.${system}.iso;
      };
    };
}
