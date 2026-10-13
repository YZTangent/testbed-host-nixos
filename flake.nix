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

    # Flake dev shell: simply run `nix develop` to enter the complete GROD / Safari environment
    devShells.x86_64-linux = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
    in {
      default = pkgs.mkShell {
        name = "grod-safari-env";

        buildInputs = with pkgs; [
          python312
          uv
          ffmpeg
          pkg-config
          git
          gcc
          gnumake
          binutils
          libGL
          glib
          zlib
          stdenv.cc.cc.lib
          cudaPackages.cudatoolkit
          linuxPackages.nvidia_x11
        ];

        shellHook = ''
          export VENV_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/grod-venv"
          if [ ! -d "$VENV_DIR" ]; then
            echo "==> Bootstrapping GROD Python 3.12 virtualenv with uv at $VENV_DIR..."
            mkdir -p "$(dirname "$VENV_DIR")"
            uv venv "$VENV_DIR" --python ${pkgs.python312}/bin/python3.12
            source "$VENV_DIR/bin/activate"
            echo "==> Installing PyTorch CUDA 12.8 and Safari SDK..."
            uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
            uv pip install safari-sdk "git+https://github.com/huggingface/lerobot.git" absl-py datasets "lerobot[dataset]"
          else
            source "$VENV_DIR/bin/activate"
          fi

          echo "==> GROD Safari environment ready. Type 'flywheel-cli' to run."
        '';
      };
    };
  };
}
