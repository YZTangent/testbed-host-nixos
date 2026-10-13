# NixOS Configuration for AMD B850 + NVIDIA RTX 5090 (GROD Inference Workstation)

Tailored NixOS configuration implementing the requirements from the **GROD Inference on RTX 5090 — Workstation Setup Guide**.

## Key Highlights & Solved Pain Points

1. **RTX 5090 (Blackwell GB202) Driver & Black Screen Prevention**:
   - `nouveau` is strictly blacklisted to prevent installer/boot hangs.
   - Pinned to `pkgs.linuxPackages_latest` and `hardware.nvidia.package = latest` (R570+ open kernel module series).
   - Modesetting and Wayland explicit sync enabled for GNOME 46+.

2. **B850 Wi-Fi 7 & 5GbE Bring-Up**:
   - Upstream Linux firmware (`hardware.enableRedistributableFirmware = true`) and `linuxPackages_latest` provide upstream drivers for MediaTek MT7902/MT7921/MT7925 and Realtek NICs.
   - Built-in USB tethering support (`rndis_host`, `cdc_ether`, `cdc_ncm`) as immediate fail-safe during installation.

3. **Docker Engine + NVIDIA Container Toolkit (CDI)**:
   - Configured out-of-the-box for `docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi`.
   - Team users automatically added to the `docker` group for non-root execution.

4. **Nix-LD for PyTorch & Safari SDK**:
   - `programs.nix-ld.enable = true` allows unmodified pip-installed wheels (`torch cu128`, `safari-sdk`, `lerobot`, `gemini-robotics-sdk`) to run seamlessly inside virtualenvs without dynamic linker errors.

5. **Multi-User Team Isolation**:
   - Dedicated user accounts for `tanyuanzheng`, `jiehao`, `zhin`, and `danielkun` with isolated home environments and SSH access.

---

## Installation Steps on Target Machine

### 1. Boot Installer Media
- Boot standard NixOS minimal installer or build the custom ISO using:
  ```bash
  nix build .#iso
  # or simply:
  nix build
  ```
- *If encountering black screen on generic media*: Add `nomodeset` in GRUB/systemd-boot kernel parameters.
- *If Wi-Fi is not detected*: Plug in smartphone via USB and enable **USB Tethering**.

### 2. Disk Partitioning & Mount
Format target NVMe disk (e.g. `/dev/nvme0n1`):
```bash
# Example EFI + Root partition
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1024MiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root ext4 1024MiB 100%

mkfs.fat -F 32 -n boot /dev/nvme0n1p1
mkfs.ext4 -L nixos /dev/nvme0n1p2

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
```

### 3. Clone Config & Generate Hardware Config
```bash
git clone https://github.com/<your-repo>/nixos-b850-5090 /mnt/etc/nixos
nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hosts/workstation/hardware-configuration.nix
```

### 4. Install & Reboot
```bash
nixos-install --flake /mnt/etc/nixos#workstation
reboot
```

---

## Post-Boot Verification & Workflow

### 1. Verify GPU & Docker Passthrough
```bash
# Check host driver (should show RTX 5090, Driver >= 570)
nvidia-smi

# Check Docker GPU passthrough (Step 8 from guide)
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

### 2. Enter GROD & Safari Environment from Anywhere (`grod`)
A global `grod` command is available across the entire filesystem:
```bash
# Enter interactive GROD subshell in your current directory:
grod

# Or execute a command directly inside the environment:
grod flywheel-cli --help

# Force a clean rebuild of the environment (~/.local/share/grod-venv):
grod --rebuild
```
On first run, `grod` uses `uv` to bootstrap Python 3.12, PyTorch CUDA 12.8 (`sm_120`), Safari SDK, and LeRobot into `~/.local/share/grod-venv`.

### 3. Run GROD Inference
```bash
grod
flywheel-cli download --artifact_id=grod_model_server_docker_v1_2_1
flywheel-cli serve \
  --training_recipe=gemini_robotics_on_device_v1 \
  --model_checkpoint_path="$HOME/grod-v1/checkpoint-runs/<checkpoint>.chkpt" \
  --docker_tag=1.2.1
```
