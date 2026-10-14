{
  description = "NixOS configuration for AMD B850 + NVIDIA RTX 5090 LLM/VLM Inference Workstation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    nixosConfigurations = {
      # Target Machine: B850 + RTX 5090 Workstation
      workstation = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/workstation
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.tanyuanzheng = import ./home;
          }
        ];
      };

      # Custom Installer ISO with latest Linux kernel + Wi-Fi 7 firmware baked in
      installer-iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/installer/iso.nix
        ];
      };
    };

    # Convenient shortcuts: `nix build .#iso` or simply `nix build`
    packages.x86_64-linux = {
      iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
      default = self.packages.x86_64-linux.iso;
    };
  };
}
