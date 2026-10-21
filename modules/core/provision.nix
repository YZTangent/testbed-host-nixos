{ pkgs }:

let
  updateRepoScript = pkgs.writers.writePython3 "prata-update-inventory" { } ''
    import pathlib
    import re
    import sys

    DEFAULT_SWAP_PERCENT = 20
    DEFAULT_SWAP_MAX_GIB = 128
    PLACEHOLDER_ADMIN_KEY = (
        "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    )

    repo_root = pathlib.Path(sys.argv[1])
    host_name = sys.argv[2]
    profile = sys.argv[3]
    disk_device = sys.argv[4]
    pub_key = sys.argv[5]

    if not re.fullmatch(r"[a-zA-Z0-9_-]+", host_name):
        raise SystemExit(f"Invalid hostName: {host_name}")
    if profile and profile not in ("prod", "dev"):
        raise SystemExit(f"Invalid profile: {profile}")
    if disk_device and not re.fullmatch(r"/[a-zA-Z0-9/_.-]+", disk_device):
        raise SystemExit(f"Invalid diskDevice: {disk_device}")
    if not re.fullmatch(r"age1[a-z0-9]+", pub_key):
        raise SystemExit(f"Invalid age public key: {pub_key}")

    inv_path = repo_root / "config" / "inventory.nix"
    inv_text = inv_path.read_text()

    escaped_host = re.escape(host_name)
    block_pattern = re.compile(
        rf"(\b{escaped_host}\s*=\s*\{{(?:[^{{}}]|\{{[^{{}}]*\}})*?\}};)",
        re.DOTALL,
    )
    block_match = block_pattern.search(inv_text)
    if block_match:
        block = block_match.group(1)
        if profile:
            block = re.sub(
                r'(profile\s*=\s*)"[^"]*"(;)',
                rf'\1"{profile}"\2',
                block,
                count=1,
            )
        if disk_device:
            block = re.sub(
                r'(diskDevice\s*=\s*)"[^"]*"(;)',
                rf'\1"{disk_device}"\2',
                block,
                count=1,
            )
        block = re.sub(
            r'(agePublicKey\s*=\s*)(null|"[^"]*")(;)',
            rf'\1"{pub_key}"\3',
            block,
            count=1,
        )
        start, end = block_match.span(1)
        inv_text = inv_text[:start] + block + inv_text[end:]
    else:
        resolved_profile = profile or "prod"
        resolved_disk = disk_device or "/dev/nvme0n1"
        entry = (
            f"  {host_name} = {{\n"
            f'    hostName = "{host_name}";\n'
            f'    profile = "{resolved_profile}";\n'
            f'    diskDevice = "{resolved_disk}";\n'
            f'    agePublicKey = "{pub_key}";\n'
            f"    swap = {{\n"
            f"      enable = true;\n"
            f"      diskPercent = {DEFAULT_SWAP_PERCENT};\n"
            f"      maxSizeGiB = {DEFAULT_SWAP_MAX_GIB};\n"
            f"    }};\n"
            f"  }};\n"
        )
        last_brace = inv_text.rfind("}")
        if last_brace == -1:
            raise SystemExit("Malformed config/inventory.nix: missing '}'")
        inv_text = inv_text[:last_brace] + entry + inv_text[last_brace:]

    inv_path.write_text(inv_text)

    # Extract all non-null host public keys from config/inventory.nix
    host_key_re = (
        r"([a-zA-Z0-9_-]+)\s*=\s*\{(?:[^{}]|\{[^{}]*\})*?"
        r'agePublicKey\s*=\s*"(age1[a-z0-9]+)"'
    )
    host_keys = {}
    for match in re.finditer(host_key_re, inv_text, re.DOTALL):
        host_keys[match.group(1)] = match.group(2)

    sops_path = repo_root / "secrets" / ".sops.yaml"
    sops_text = sops_path.read_text() if sops_path.exists() else ""
    admin_match = re.search(r"-\s*&admin\s+(age1[a-z0-9]+)", sops_text)
    admin_key = (
        admin_match.group(1) if admin_match else PLACEHOLDER_ADMIN_KEY
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
    findutils
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
    PROFILE=""
    DISK_DEV=""
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
          if [ $# -lt 2 ]; then
            echo "ERROR: --profile requires an argument ('prod' or 'dev')." >&2
            exit 1
          fi
          PROFILE="$2"
          if [ "$PROFILE" != "prod" ] && [ "$PROFILE" != "dev" ]; then
            echo "ERROR: --profile must be 'prod' or 'dev' (got '$PROFILE')." >&2
            exit 1
          fi
          shift 2
          ;;
        --disk)
          if [ $# -lt 2 ]; then
            echo "ERROR: --disk requires a block device path." >&2
            exit 1
          fi
          DISK_DEV="$2"
          shift 2
          ;;
        --flash)
          if [ $# -lt 2 ]; then
            echo "ERROR: --flash requires a target USB block device path." >&2
            exit 1
          fi
          FLASH_DEV="$2"
          shift 2
          ;;
        --target)
          if [ $# -lt 2 ]; then
            echo "ERROR: --target requires an SSH destination (user@ip)." >&2
            exit 1
          fi
          TARGET_SSH="$2"
          shift 2
          ;;
        --repo)
          if [ $# -lt 2 ]; then
            echo "ERROR: --repo requires a directory path." >&2
            exit 1
          fi
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

    if [[ ! "$HOST_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "ERROR: Invalid hostName '$HOST_NAME' (must match [a-zA-Z0-9_-]+)." >&2
      exit 1
    fi

    if [ -n "$DISK_DEV" ] && [[ ! "$DISK_DEV" =~ ^/[a-zA-Z0-9/_.-]+$ ]]; then
      echo "ERROR: Invalid disk device '$DISK_DEV'." >&2
      exit 1
    fi

    if [ -n "$FLASH_DEV" ] && [[ ! "$FLASH_DEV" =~ ^/[a-zA-Z0-9/_.-]+$ ]]; then
      echo "ERROR: Invalid flash device '$FLASH_DEV'." >&2
      exit 1
    fi

    if [ -n "$TARGET_SSH" ] && [[ ! "$TARGET_SSH" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._:-]+$ ]]; then
      echo "ERROR: Invalid SSH target '$TARGET_SSH' (expected user@host)." >&2
      exit 1
    fi

    # 1. Create ephemeral directory strictly in RAM (/dev/shm) and guarantee cleanup on exit
    umask 0077
    SHM_BASE="/dev/shm"
    if [ ! -d "$SHM_BASE" ] || [ ! -w "$SHM_BASE" ]; then
      echo "ERROR: /dev/shm is not available or writable; refusing to write age private key to disk." >&2
      exit 1
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
