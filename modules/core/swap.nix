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
