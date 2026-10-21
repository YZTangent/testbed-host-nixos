# Declarative Testbed Inventory, Secret Key Provisioning & 1-Step Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual NixOS disk partitioning, hardcoded single-host/single-user configuration, and post-boot SSH-to-age key extraction with a checked-in testbed inventory (`config/inventory.nix`), `prod`/`dev` testbed profiles (`prata.profile`), configurable dynamic swap (`min(20%, 128 GiB)`), `disko` declarative partitioning, and an ephemeral in-memory `provision-testbed` / `install-testbed` workflow.

**Architecture:** A shared Golden OS module tree (`modules/` + `hosts/workstation`) is parameterized by `config/inventory.nix` in `flake.nix` to produce `nixosConfigurations.<hostName>`. `modules/core/users.nix` defines `prata.profile` (`"prod"` vs `"dev"`): `prod` beds create only `prata-admin` and `prata` (no Home Manager), whereas `dev` beds additionally create `prata.devUsers` (`tanyuanzheng`, `jiehao`, `zhin`, `danielkun`) wired to Home Manager (`home/default.nix`). On the dev/cloudtop machine, `nix run .#provision -- <hostName>` generates the machine's `age` private key strictly in `/dev/shm`, updates `config/inventory.nix` and `secrets/.sops.yaml` with the public key, runs `sops updatekeys`, and either encrypts the private key in RAM with a One-Time PIN (`keys.age`)—shredding the plaintext key before baking `/etc/sops/age/keys.age` into the installer ISO—or pushes it via `nixos-anywhere --extra-files` before wiping `/dev/shm`.

**Tech Stack:** Nix Flakes, NixOS (`nixos-unstable`), `home-manager`, `sops-nix`, `disko`, `nixos-anywhere`, `age`, Bash, Python 3 (for structured inventory/YAML updates in `provision-testbed`).

**Workspace Copy:** [`docs/changes/2026-10-21-testbed-secrets-provisioning-plan.md`](file:///usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning/docs/changes/2026-10-21-testbed-secrets-provisioning-plan.md)

---

### Task 1: Declarative Inventory (`config/inventory.nix`), Prod/Dev User Profiles (`modules/core/users.nix`), Default Hostname, and SOPS Key Configuration

**Files:**
- Create: `.gitignore`
- Create: `config/inventory.nix`
- Move & Modify: `.sops.yaml` -> `secrets/.sops.yaml`
- Modify: `modules/core/users.nix`
- Modify: `modules/core/packages.nix`
- Modify: `home/default.nix`
- Modify: `modules/core/network.nix:1-10`
- Modify: `modules/core/sops.nix:1-28`

- [x] **Step 1: Verify current inventory, profile option, hostname, and SOPS config fail the new expectations**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
test -f config/inventory.nix && test -f secrets/.sops.yaml
```
Expected: FAIL (exit code 1; `config/inventory.nix` and `secrets/.sops.yaml` do not exist yet).

- [x] **Step 2: Create `.gitignore`, `config/inventory.nix`, move `.sops.yaml` to `secrets/.sops.yaml`, and update `users.nix`, `packages.nix`, `home/default.nix`, `network.nix`, and `sops.nix`**

Create `.gitignore`:
```gitignore
result
result-*
.worktree/
```

Create `config/inventory.nix`:
```nix
{
  prata-host = {
    hostName = "prata-host";
    profile = "prod";
    diskDevice = "/dev/nvme0n1";
    agePublicKey = null;
    swap = {
      enable = true;
      diskPercent = 20;
      maxSizeGiB = 128;
    };
  };
}
```

Remove root `.sops.yaml` (`git rm .sops.yaml`) and create `secrets/.sops.yaml`:
```yaml
# Managed by `nix run .#provision -- <hostName>`
# Edit encrypted secrets with:
#   sops --config secrets/.sops.yaml secrets/secrets.yaml

keys:
  - &admin age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

creation_rules:
  - path_regex: ^secrets\.yaml$
    key_groups:
      - age:
          - *admin
```

Update `modules/core/users.nix` so `prod` beds only have `prata-admin` and `prata` (no Home Manager), and `dev` beds additionally enable `prata.devUsers` with Home Manager:
```nix
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
```

Update `modules/core/packages.nix` (adding `fd` and `zoxide` system-wide):
```nix
{ pkgs, ... }:

{
  # Allow proprietary packages (NVIDIA drivers, CUDA, etc.)
  nixpkgs.config.allowUnfree = true;

  # Nix daemon settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # Weekly garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Base system utilities and hardware monitoring
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    tree
    jq
    tmux
    ripgrep
    fd
    zoxide

    # GPU and hardware monitoring
    nvtopPackages.nvidia
    pciutils
    usbutils
    lm_sensors
    htop
  ];
}
```

Update `home/default.nix` (removing `fd`, which is now system-wide):
```nix
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
```

Update `modules/core/network.nix`:
```nix
{ lib, ... }:

{
  networking.hostName = lib.mkDefault "prata-host";
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
}
```

Update `modules/core/sops.nix`:
```nix
{ lib, pkgs, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
  hasSecrets = builtins.pathExists secretsFile;
in
{
  # SOPS & Age CLI tools for managing encrypted secrets
  environment.systemPackages = with pkgs; [
    sops
    age
  ];

  # Dedicated per-testbed age private key provisioned into /var/lib/sops-nix/keys
  sops.age.keyFile = "/var/lib/sops-nix/keys";

  # Activate secret decryption automatically once secrets/secrets.yaml is created
  sops.defaultSopsFile = lib.mkIf hasSecrets secretsFile;

  sops.secrets = lib.mkIf hasSecrets {
    safari_api_key = {
      # Readable by all team members in the 'docker' group; grod copies it to ~/.config/safari_sdk/API_KEY
      group = "docker";
      mode = "0440";
    };
  };
}
```

- [x] **Step 3: Run evaluation checks to verify `config/inventory.nix`, `network.nix`, and `sops.nix`**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
nix eval --impure --expr '(import ./config/inventory.nix).prata-host.hostName'
nix eval --impure --expr '(import ./config/inventory.nix).prata-host.profile'
nix eval .#nixosConfigurations.workstation.config.networking.hostName
nix eval .#nixosConfigurations.workstation.config.sops.age.keyFile
```
Expected:
```
"prata-host"
"prod"
"prata-host"
"/var/lib/sops-nix/keys"
```

- [x] **Step 4: Strictly follow the implementer's subagents**

Ensure to strictly follow the implementer's subagents workflow within the SDLC verification loop to handle any code reviews (regressions, sanitation, vulnerability) and ensure quality before committing.

- [x] **Step 5: Commit Task 1**

```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
git add .gitignore config/inventory.nix secrets/.sops.yaml modules/core/users.nix modules/core/packages.nix home/default.nix modules/core/network.nix modules/core/sops.nix
git rm --cached --ignore-unmatch .sops.yaml
git commit -m "feat(core): add config/inventory.nix, prod/dev user profiles, and dedicated sops age keyFile"
```

---

### Task 2: Declarative Disk Layout (`modules/core/disko.nix`), Configurable Dynamic Swap (`modules/core/swap.nix`), and `mkTestbed` in `flake.nix`

**Files:**
- Create: `modules/core/disko.nix`
- Create: `modules/core/swap.nix`
- Modify: `modules/core/default.nix`
- Modify: `hosts/workstation/hardware-configuration.nix`
- Modify: `flake.nix`

- [x] **Step 1: Verify `prata.swap` and `prata.diskDevice` options do not exist yet**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
nix eval .#nixosConfigurations.workstation.config.prata.swap.maxSizeGiB
```
Expected: FAIL with `error: attribute 'swap' missing`.

- [x] **Step 2: Create `modules/core/disko.nix` and `modules/core/swap.nix`, and wire into `modules/core/default.nix`, `hardware-configuration.nix`, and `flake.nix`**

Create `modules/core/disko.nix`:
```nix
{ config, lib, ... }:

{
  options.prata.diskDevice = lib.mkOption {
    type = lib.types.str;
    default = "/dev/nvme0n1";
    description = "Primary block device formatted by disko for the testbed OS.";
  };

  config = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = config.prata.diskDevice;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1024M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "fmask=0077" "dmask=0077" ];
                  extraArgs = [ "-n" "boot" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  extraArgs = [ "-L" "nixos" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
```

Create `modules/core/swap.nix`:
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.prata.swap;

  calcSwapMibScript = pkgs.writeShellScriptBin "prata-calc-swap-mib" ''
    set -euo pipefail
    DISK_BYTES="$1"
    PERCENT="${toString cfg.diskPercent}"
    MAX_GIB="${toString cfg.maxSizeGiB}"

    PCT_BYTES=$(( (DISK_BYTES / 100) * PERCENT ))
    MAX_BYTES=$(( MAX_GIB * 1024 * 1024 * 1024 ))

    if [ "$PCT_BYTES" -lt "$MAX_BYTES" ]; then
      TARGET_BYTES="$PCT_BYTES"
    else
      TARGET_BYTES="$MAX_BYTES"
    fi

    TARGET_MIB=$(( TARGET_BYTES / (1024 * 1024) ))
    echo "$TARGET_MIB"
  '';
in
{
  options.prata.swap = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to dynamically allocate and activate /var/swapfile on boot.";
    };

    diskPercent = lib.mkOption {
      type = lib.types.ints.between 1 90;
      default = 20;
      description = "Target swap allocation as a percentage of root disk capacity.";
    };

    maxSizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 128;
      description = "Maximum swap allocation cap in GiB.";
    };

    calcScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = calcSwapMibScript;
      description = "Helper script package for computing swap size in MiB.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.prata-swapfile = {
      description = "Dynamically allocate and activate /var/swapfile (min(${toString cfg.diskPercent}%, ${toString cfg.maxSizeGiB}GiB))";
      wantedBy = [ "multi-user.target" ];
      before = [ "swap.target" ];
      after = [ "local-fs.target" ];
      path = with pkgs; [
        coreutils
        util-linux
        procps
        calcSwapMibScript
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        SWAPFILE="/var/swapfile"

        if [ ! -f "$SWAPFILE" ]; then
          ROOT_SOURCE="$(findmnt -n -o SOURCE /)"
          DISK_BYTES="$(lsblk -b -d -n -o SIZE "$ROOT_SOURCE" 2>/dev/null || df --output=size -B1 / | tail -n1 | tr -d ' ')"
          SWAP_MIB="$(prata-calc-swap-mib "$DISK_BYTES")"

          if [ "$SWAP_MIB" -gt 0 ]; then
            echo "==> Allocating ''${SWAP_MIB}MiB swapfile at $SWAPFILE..."
            fallocate -l "''${SWAP_MIB}M" "$SWAPFILE"
            chmod 0600 "$SWAPFILE"
            mkswap "$SWAPFILE"
          fi
        fi

        if [ -f "$SWAPFILE" ] && ! grep -qF "$SWAPFILE" /proc/swaps; then
          swapon "$SWAPFILE"
        fi
      '';
    };
  };
}
```

Update `modules/core/default.nix`:
```nix
{ ... }:

{
  imports = [
    ./packages.nix
    ./network.nix
    ./users.nix
    ./nix-ld.nix
    ./sops.nix
    ./disko.nix
    ./swap.nix
  ];

  time.timeZone = "Asia/Singapore";
  i18n.defaultLocale = "en_US.UTF-8";

  # Disable documentation building to avoid upstream Sphinx/python-doc build failures
  documentation = {
    enable = false;
    doc.enable = false;
    man.enable = false;
    info.enable = false;
    nixos.enable = false;
  };
}
```

Update `hosts/workstation/hardware-configuration.nix`:
```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
```

Update `flake.nix` to include `disko` input and map `config/inventory.nix` via `mkTestbed` (without hardcoding `home-manager.users.tanyuanzheng` in `mkTestbed`):
```nix
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
```

- [x] **Step 3: Run tests to verify `prod` vs `dev` user/Home Manager gating, `disko`, and dynamic swap calculation (`min(20%, 128 GiB)`)**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
nix eval .#nixosConfigurations.prata-host.config.prata.profile
nix eval --json .#nixosConfigurations.prata-host.config.home-manager.users --apply builtins.attrNames
nix eval .#nixosConfigurations.prata-host.config.users.users.prata-admin.isNormalUser
nix eval .#nixosConfigurations.prata-host.config.users.users.prata.isNormalUser
nix eval .#nixosConfigurations.prata-host.config.prata.diskDevice
nix eval .#nixosConfigurations.prata-host.config.prata.swap.maxSizeGiB
nix eval .#nixosConfigurations.prata-host.config.fileSystems.\"/\".device
CALC_BIN="$(nix build .#nixosConfigurations.prata-host.config.prata.swap.calcScript --no-link --print-out-paths)/bin/prata-calc-swap-mib"
test "$("$CALC_BIN" 536870912000)" = "102400"
test "$("$CALC_BIN" 1073741824000)" = "131072"
echo "PASS"
```
Expected:
```
"prod"
[]
true
true
"/dev/nvme0n1"
128
"/dev/disk/by-partlabel/disk-main-root"
PASS
```

- [x] **Step 4: Strictly follow the implementer's subagents**

Ensure to strictly follow the implementer's subagents workflow within the SDLC verification loop to handle any code reviews (regressions, sanitation, vulnerability) and ensure quality before committing.

- [x] **Step 5: Commit Task 2**

```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
git add flake.nix flake.lock modules/core/disko.nix modules/core/swap.nix modules/core/default.nix hosts/workstation/hardware-configuration.nix
git commit -m "feat(storage): add disko declarative partitioning, dynamic swapfile, and clean mkTestbed"
```

---

### Task 3: Target Bare-Metal Installer & Ephemeral ISO Age Key Embedding (`modules/installer/iso.nix`)

**Files:**
- Modify: `modules/installer/iso.nix`

- [x] **Step 1: Verify `install-testbed` is not yet present in `installer-iso`**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
nix eval --json .#nixosConfigurations.installer-iso.config.environment.systemPackages --apply 'pkgs: map (p: p.pname or p.name or "") pkgs' | grep -q "install-testbed"
```
Expected: FAIL (exit code 1).

- [x] **Step 2: Update `modules/installer/iso.nix` to embed ephemeral `/etc/sops/age/keys` when `PRATA_ISO_AGE_KEY_FILE` is provided and ship `install-testbed`**

Update `modules/installer/iso.nix`:
```nix
# Custom installer ISO with bleeding-edge kernel, Wi-Fi 7 firmware, nouveau blacklisted,
# optional embedded per-testbed age private key (/etc/sops/age/keys), and 1-step `install-testbed` CLI.
{ inputs, lib, pkgs, modulesPath, ... }:

let
  isoAgeKeyEnv = builtins.getEnv "PRATA_ISO_AGE_KEY_FILE";
  hasIsoAgeKey = isoAgeKeyEnv != "" && builtins.pathExists isoAgeKeyEnv;
  defaultTargetHost =
    let
      envHost = builtins.getEnv "PRATA_ISO_TARGET_HOST";
    in
    if envHost != "" then envHost else "prata-host";

  installTestbed = pkgs.writeShellScriptBin "install-testbed" ''
    set -euo pipefail

    HOST="''${1:-${defaultTargetHost}}"
    FLAKE_SRC="''${PRATA_FLAKE_URI:-/etc/prata-nixos}"

    if [ "$(id -u)" -ne 0 ]; then
      echo "ERROR: install-testbed must be run as root (sudo install-testbed [hostName])." >&2
      exit 1
    fi

    echo "==> Formatting and mounting disks for host '$HOST' via disko..."
    ${inputs.disko.packages.${pkgs.system}.disko}/bin/disko \
      --mode destroy,format,mount \
      --flake "''${FLAKE_SRC}#''${HOST}"

    if [ -f "/etc/sops/age/keys" ]; then
      echo "==> Installing pre-baked age private key to /mnt/var/lib/sops-nix/keys..."
      install -d -m 0700 /mnt/var/lib/sops-nix
      install -m 0400 -o 0 -g 0 /etc/sops/age/keys /mnt/var/lib/sops-nix/keys
    else
      echo "WARNING: /etc/sops/age/keys not found on ISO; target will boot without pre-staged SOPS key." >&2
    fi

    echo "==> Installing NixOS configuration ''${FLAKE_SRC}#''${HOST}..."
    nixos-install --flake "''${FLAKE_SRC}#''${HOST}" --no-root-passwd

    echo "==> Installation complete for '$HOST'. You may now reboot."
  '';
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # Bleeding-edge kernel so MediaTek MT7902/MT7921/MT7925 and Realtek NICs are recognized
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Include all proprietary firmware
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.linux-firmware ];

  # CRITICAL: Blacklist nouveau to avoid black screen hang on RTX 5090 Blackwell during boot
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelParams = [ "nomodeset" ];

  # USB tethering modules pre-loaded
  boot.kernelModules = [
    "rndis_host"
    "cdc_ether"
    "cdc_ncm"
  ];

  # NetworkManager for convenient wifi-menu or nmcli during installation
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # Embed a clean copy of the repo flake at /etc/prata-nixos and optional age key at /etc/sops/age/keys
  environment.etc = {
    "prata-nixos".source = inputs.self;
  } // lib.optionalAttrs hasIsoAgeKey {
    "sops/age/keys" = {
      source = /. + isoAgeKeyEnv;
      mode = "0400";
      uid = 0;
      gid = 0;
    };
  };

  # Useful utilities + 1-step installer on the live media
  environment.systemPackages = with pkgs; [
    git
    pciutils
    usbutils
    neovim
    htop
    curl
    age
    sops
    inputs.disko.packages.${pkgs.system}.disko
    installTestbed
  ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

- [x] **Step 3: Verify `install-testbed` and `/etc/sops/age/keys` injection evaluate cleanly**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
nix eval --json .#nixosConfigurations.installer-iso.config.environment.systemPackages --apply 'pkgs: map (p: p.pname or p.name or "") pkgs' | grep -q "install-testbed"
TMP_KEY="$(mktemp /dev/shm/test-age.XXXXXX)"
trap 'rm -f "$TMP_KEY"' EXIT
echo "AGE-SECRET-KEY-1TEST" > "$TMP_KEY"
PRATA_ISO_AGE_KEY_FILE="$TMP_KEY" PRATA_ISO_TARGET_HOST="prata-tb-99" nix eval --impure .#nixosConfigurations.installer-iso.config.environment.etc.\"sops/age/keys\".mode
rm -f "$TMP_KEY"
```
Expected:
```
"0400"
```

- [x] **Step 4: Strictly follow the implementer's subagents**

Ensure to strictly follow the implementer's subagents workflow within the SDLC verification loop to handle any code reviews (regressions, sanitation, vulnerability) and ensure quality before committing.

- [x] **Step 5: Commit Task 3**

```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
git add modules/installer/iso.nix
git commit -m "feat(iso): embed ephemeral age private key and ship 1-step install-testbed CLI"
```

---

### Task 4: Ephemeral Dev/Cloudtop Provisioning Utility (`modules/core/provision.nix`), Flake App Exposure, and Docs

**Files:**
- Create: `modules/core/provision.nix`
- Modify: `flake.nix`
- Modify: `README.md`

- [x] **Step 1: Verify `.#provision` flake output does not exist yet**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
nix eval .#packages.x86_64-linux.provision.name
```
Expected: FAIL with `error: flake ... does not provide attribute 'packages.x86_64-linux.provision'`.

- [x] **Step 2: Create `modules/core/provision.nix` and wire `.#provision` into `flake.nix` and `README.md`**

Create `modules/core/provision.nix`:
```nix
{ pkgs }:

let
  updateRepoScript = pkgs.writers.writePython3 "prata-update-inventory" { } ''
    import pathlib
    import re
    import sys

    repo_root = pathlib.Path(sys.argv[1])
    host_name = sys.argv[2]
    profile = sys.argv[3]
    disk_device = sys.argv[4]
    pub_key = sys.argv[5]

    inv_path = repo_root / "config" / "inventory.nix"
    inv_text = inv_path.read_text()

    host_pattern = re.compile(
        rf"(\b{re.escape(host_name)}\s*=\s*\{{[^}}]*?agePublicKey\s*=\s*)(null|\"[^\"]*\")(;)",
        re.DOTALL,
    )
    if host_pattern.search(inv_text):
        inv_text = host_pattern.sub(rf'\1"{pub_key}"\3', inv_text, count=1)
    else:
        entry = (
            f"  {host_name} = {{\n"
            f'    hostName = "{host_name}";\n'
            f'    profile = "{profile}";\n'
            f'    diskDevice = "{disk_device}";\n'
            f'    agePublicKey = "{pub_key}";\n'
            f"    swap = {{\n"
            f"      enable = true;\n"
            f"      diskPercent = 20;\n"
            f"      maxSizeGiB = 128;\n"
            f"    }};\n"
            f"  }};\n"
        )
        last_brace = inv_text.rfind("}")
        inv_text = inv_text[:last_brace] + entry + inv_text[last_brace:]

    inv_path.write_text(inv_text)

    # Extract all non-null host public keys from config/inventory.nix
    host_keys = {}
    for match in re.finditer(
        r"([a-zA-Z0-9_-]+)\s*=\s*\{[^}]*?agePublicKey\s*=\s*\"(age1[a-z0-9]+)\"",
        inv_text,
        re.DOTALL,
    ):
        host_keys[match.group(1)] = match.group(2)

    sops_path = repo_root / "secrets" / ".sops.yaml"
    sops_text = sops_path.read_text() if sops_path.exists() else ""
    admin_match = re.search(r"-\s*&admin\s+(age1[a-z0-9]+)", sops_text)
    admin_key = (
        admin_match.group(1)
        if admin_match
        else "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    )

    lines = [
        "# Managed by `nix run .#provision -- <hostName>`",
        "# Edit encrypted secrets with:",
        "#   sops --config secrets/.sops.yaml secrets/secrets.yaml",
        "",
        "keys:",
        f"  - &admin {admin_key}",
    ]
    for h_name, h_key in sorted(host_keys.items()):
        anchor = re.sub(r"[^a-zA-Z0-9_]", "_", h_name)
        lines.append(f"  - &host_{anchor} {h_key}")

    lines.extend(
        [
            "",
            "creation_rules:",
            "  - path_regex: ^secrets\\.yaml$",
            "    key_groups:",
            "      - age:",
            "          - *admin",
        ]
    )
    for h_name in sorted(host_keys.keys()):
        anchor = re.sub(r"[^a-zA-Z0-9_]", "_", h_name)
        lines.append(f"          - *host_{anchor}")

    sops_path.write_text("\n".join(lines) + "\n")
  '';
in
pkgs.writeShellApplication {
  name = "provision-testbed";
  runtimeInputs = with pkgs; [
    age
    sops
    coreutils
    gnugrep
    gnused
    nixos-anywhere
  ];
  text = ''
    usage() {
      cat <<EOF
    Usage: provision-testbed <hostName> [options]

    Options:
      --profile <prod|dev> Testbed build profile in config/inventory.nix (default: prod)
      --disk <device>      Target NVMe disk device in config/inventory.nix (default: /dev/nvme0n1)
      --flash <usb-dev>    Write the built ISO with embedded age key directly to <usb-dev> via dd
      --target <user@ip>   Deploy directly over SSH via nixos-anywhere --extra-files (instead of building ISO)
      --repo <path>        Path to repository root (default: current working directory)
      --dry-run            Generate ephemeral key in /dev/shm, update inventory & .sops.yaml, and exit without building ISO
    EOF
    }

    if [ $# -lt 1 ]; then
      usage
      exit 1
    fi

    HOST_NAME=""
    PROFILE="prod"
    DISK_DEV="/dev/nvme0n1"
    FLASH_DEV=""
    TARGET_SSH=""
    REPO_ROOT="$(pwd)"
    DRY_RUN=0

    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help)
          usage
          exit 0
          ;;
        --profile)
          PROFILE="$2"
          if [ "$PROFILE" != "prod" ] && [ "$PROFILE" != "dev" ]; then
            echo "ERROR: --profile must be 'prod' or 'dev' (got '$PROFILE')." >&2
            exit 1
          fi
          shift 2
          ;;
        --disk)
          DISK_DEV="$2"
          shift 2
          ;;
        --flash)
          FLASH_DEV="$2"
          shift 2
          ;;
        --target)
          TARGET_SSH="$2"
          shift 2
          ;;
        --repo)
          REPO_ROOT="$2"
          shift 2
          ;;
        --dry-run)
          DRY_RUN=1
          shift
          ;;
        -*)
          echo "ERROR: Unknown flag $1" >&2
          usage
          exit 1
          ;;
        *)
          if [ -z "$HOST_NAME" ]; then
            HOST_NAME="$1"
            shift
          else
            echo "ERROR: Unexpected argument $1" >&2
            usage
            exit 1
          fi
          ;;
      esac
    done

    if [ -z "$HOST_NAME" ]; then
      echo "ERROR: <hostName> is required." >&2
      usage
      exit 1
    fi

    # 1. Create ephemeral directory strictly in RAM (/dev/shm) and guarantee cleanup on exit
    SHM_BASE="/dev/shm"
    if [ ! -d "$SHM_BASE" ] || [ ! -w "$SHM_BASE" ]; then
      SHM_BASE="''${TMPDIR:-/tmp}"
    fi
    SHM_DIR="$(mktemp -d "$SHM_BASE/prata-provision.XXXXXX")"
    cleanup() {
      if [ -d "$SHM_DIR" ]; then
        find "$SHM_DIR" -type f -exec shred -u {} + 2>/dev/null || true
        rm -rf "$SHM_DIR"
      fi
    }
    trap cleanup EXIT INT TERM

    install -d -m 0700 "$SHM_DIR/var/lib/sops-nix"
    KEY_FILE="$SHM_DIR/var/lib/sops-nix/keys"

    echo "==> Generating ephemeral age keypair in RAM for '$HOST_NAME'..."
    age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 0400 "$KEY_FILE"
    PUB_KEY="$(age-keygen -y "$KEY_FILE")"
    echo "==> Derived public key: $PUB_KEY"

    # 2. Update config/inventory.nix and secrets/.sops.yaml
    echo "==> Updating config/inventory.nix and secrets/.sops.yaml..."
    ${updateRepoScript} "$REPO_ROOT" "$HOST_NAME" "$PROFILE" "$DISK_DEV" "$PUB_KEY"

    # 3. Re-key secrets/secrets.yaml if present
    if [ -f "$REPO_ROOT/secrets/secrets.yaml" ]; then
      echo "==> Running sops updatekeys on secrets/secrets.yaml..."
      (cd "$REPO_ROOT/secrets" && sops --config .sops.yaml updatekeys -y secrets.yaml)
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "==> Dry run complete. Ephemeral private key will now be shredded from RAM."
      exit 0
    fi

    # 4. Provision via Remote SSH (nixos-anywhere) OR Build/Flash Installer ISO
    if [ -n "$TARGET_SSH" ]; then
      echo "==> Provisioning '$HOST_NAME' remotely on '$TARGET_SSH' via nixos-anywhere..."
      nixos-anywhere \
        --extra-files "$SHM_DIR" \
        --flake "''${REPO_ROOT}#''${HOST_NAME}" \
        "$TARGET_SSH"
    else
      echo "==> Building installer ISO with embedded age key for '$HOST_NAME'..."
      ISO_OUT="$(
        PRATA_ISO_AGE_KEY_FILE="$KEY_FILE" \
        PRATA_ISO_TARGET_HOST="$HOST_NAME" \
        nix build --impure "''${REPO_ROOT}#iso" --no-link --print-out-paths
      )"
      ISO_IMG="$(find "$ISO_OUT/iso" -name '*.iso' | head -n1)"
      echo "==> Built ISO: $ISO_IMG"

      if [ -n "$FLASH_DEV" ]; then
        echo "==> Flashing $ISO_IMG to $FLASH_DEV..."
        sudo dd if="$ISO_IMG" of="$FLASH_DEV" bs=4M status=progress conv=fsync
        sync
        echo "==> USB flash complete."
      fi
    fi
  '';
}
```

Update `flake.nix` to wire `packages.x86_64-linux.provision` and `apps.x86_64-linux.provision` (with no `home-manager.users` inside `mkTestbed`):
```nix
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
      pkgs = nixpkgs.legacyPackages.${system};
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

      provisionPkg = import ./modules/core/provision.nix { inherit pkgs; };
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
        provision = provisionPkg;
        default = self.packages.${system}.iso;
      };

      apps.${system} = {
        provision = {
          type = "app";
          program = "${provisionPkg}/bin/provision-testbed";
        };
      };
    };
}
```

Update `README.md` (lines 28-68) to document `nix run .#provision -- <hostName> [--profile prod|dev]` and `sudo install-testbed`:
```markdown
## Provisioning a New Testbed

### Option A: USB Installer ISO (Offline / Console Install)
1. On your developer / cloudtop workstation, mint the testbed's `age` key in RAM, register its public key in `config/inventory.nix` & `secrets/.sops.yaml`, and build/flash the installer ISO with the private key baked into `/etc/sops/age/keys`:
   ```bash
   # Prod bed (prata-admin + prata only, no Home Manager):
   nix run .#provision -- prata-tb-01 --flash /dev/sdX

   # Dev bed (adds team accounts managed with Home Manager):
   nix run .#provision -- prata-dev-01 --profile dev --flash /dev/sdX
   ```
2. Boot the target testbed from the USB drive and run:
   ```bash
   sudo install-testbed prata-tb-01
   reboot
   ```
   `install-testbed` formats `/dev/nvme0n1` via `disko`, copies `/etc/sops/age/keys` to `/mnt/var/lib/sops-nix/keys` (`0400`), and installs `.#prata-tb-01`. On first boot, `/var/swapfile` ($\min(20\%, 128\text{ GiB})$) and `/run/secrets/safari_api_key` are active immediately.

### Option B: Remote SSH Install (`nixos-anywhere`)
1. Boot any live NixOS installer on the target testbed and run from your workstation:
   ```bash
   nix run .#provision -- prata-tb-01 --target root@<target-ip>
   ```
```

- [x] **Step 3: Test `provision-testbed --dry-run` (both `prod` and `dev`) in an isolated temp copy and run `nix flake check`**

Run:
```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
cp -r config secrets "$TEST_DIR/"
nix run .#provision -- prata-tb-01 --repo "$TEST_DIR" --dry-run
nix run .#provision -- prata-dev-01 --profile dev --repo "$TEST_DIR" --dry-run
grep -q 'prata-tb-01' "$TEST_DIR/config/inventory.nix"
grep -q 'profile = "dev";' "$TEST_DIR/config/inventory.nix"
grep -q 'age1' "$TEST_DIR/config/inventory.nix"
grep -q 'host_prata_tb_01' "$TEST_DIR/secrets/.sops.yaml"
grep -q 'host_prata_dev_01' "$TEST_DIR/secrets/.sops.yaml"
! grep -rn "AGE-SECRET-KEY" "$TEST_DIR"
rm -rf "$TEST_DIR"
nix flake check --no-build
echo "PASS"
```
Expected:
```
PASS
```

- [x] **Step 4: Strictly follow the implementer's subagents**

Ensure to strictly follow the implementer's subagents workflow within the SDLC verification loop to handle any code reviews (regressions, sanitation, vulnerability) and ensure quality before committing.

- [x] **Step 5: Commit Task 4**

```bash
cd /usr/local/google/home/tanyuanzheng/code/nixos-b850-5090/.worktree/testbed-secrets-provisioning
git add modules/core/provision.nix flake.nix README.md
git commit -m "feat(provision): add ephemeral in-memory provision-testbed CLI and docs"
```
