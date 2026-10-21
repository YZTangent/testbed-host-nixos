# Custom installer ISO with bleeding-edge kernel, Wi-Fi 7 firmware, nouveau blacklisted,
# optional PIN-encrypted per-testbed age private key (/etc/sops/age/keys.age), and 1-step `install-testbed` CLI.
{ inputs, lib, pkgs, modulesPath, ... }:

let
  isoAgeKeyEnv = builtins.getEnv "PRATA_ISO_AGE_KEY_FILE";
  hasIsoAgeKey = isoAgeKeyEnv != "" && builtins.pathExists isoAgeKeyEnv;
  defaultTargetHost =
    let
      envHost = builtins.getEnv "PRATA_ISO_TARGET_HOST";
    in
    assert envHost == "" || builtins.match "[a-zA-Z0-9_-]+" envHost != null;
    if envHost != "" then envHost else "prata-host";

  installTestbed = pkgs.writeShellScriptBin "install-testbed" ''
    set -euo pipefail

    HOST="''${1:-${defaultTargetHost}}"
    FLAKE_SRC="''${PRATA_FLAKE_URI:-/etc/prata-nixos}"

    if [[ ! "$HOST" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "ERROR: Invalid hostName '$HOST' (must match [a-zA-Z0-9_-]+)." >&2
      exit 1
    fi

    if [ "$(id -u)" -ne 0 ]; then
      echo "ERROR: install-testbed must be run as root (sudo install-testbed [hostName])." >&2
      exit 1
    fi

    echo "==> Formatting and mounting disks for host '$HOST' via disko..."
    ${inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko}/bin/disko \
      --mode destroy,format,mount \
      --flake "''${FLAKE_SRC}#''${HOST}"

    if [ -f "/etc/sops/age/keys.age" ]; then
      echo "==> Decrypting /etc/sops/age/keys.age to /mnt/var/lib/sops-nix/keys (enter One-Time Install PIN)..."
      install -d -m 0700 -o 0 -g 0 /mnt/var/lib/sops-nix
      (
        umask 0077
        until ${pkgs.age}/bin/age -d -o /mnt/var/lib/sops-nix/keys /etc/sops/age/keys.age; do
          echo "WARNING: Decryption failed (incorrect PIN). Please try again." >&2
        done
      )
      chmod 0400 /mnt/var/lib/sops-nix/keys
      chown 0:0 /mnt/var/lib/sops-nix/keys
    elif [ -f "/etc/sops/age/keys" ]; then
      echo "==> Installing pre-baked age private key to /mnt/var/lib/sops-nix/keys..."
      install -d -m 0700 -o 0 -g 0 /mnt/var/lib/sops-nix
      install -m 0400 -o 0 -g 0 /etc/sops/age/keys /mnt/var/lib/sops-nix/keys
    else
      echo "WARNING: /etc/sops/age/keys.age not found on ISO; target will boot without pre-staged SOPS key." >&2
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

  # Embed a clean copy of the repo flake at /etc/prata-nixos and optional PIN-encrypted age key at /etc/sops/age/keys.age
  environment.etc = {
    "prata-nixos".source = inputs.self;
  } // lib.optionalAttrs hasIsoAgeKey {
    "sops/age/keys.age" = {
      text = builtins.readFile isoAgeKeyEnv;
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
    inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko
    installTestbed
  ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
