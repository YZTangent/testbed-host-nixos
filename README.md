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

5. **Prod vs Dev Testbed Profiles (`prata.profile`)**:
   - **`prod` (default)**: Provisions only `prata-admin` (`wheel`, `docker`, `video`, `networkmanager`) and `prata` (`docker`, `video`, `networkmanager`) with standard system packages (`git`, `ripgrep`, `fd`, `zoxide`, `tmux`, `nvtop`) and no Home Manager overhead.
   - **`dev`**: Adds developer accounts (`tanyuanzheng`, `jiehao`, `zhin`, `danielkun`) managed with Home Manager (`bat`, `eza`, bash/git user config).

6. **Declarative Disk Layout (`disko`), Dynamic Swap, & Ephemeral SOPS Key Provisioning**:
   - Per-testbed inventory in `config/inventory.nix` with SOPS recipients in `secrets/.sops.yaml`.
   - Automated GPT partitioning (`1024M` `/boot` ESP + `100%` ext4 `/`) via `disko` and dynamic `/var/swapfile` (`min(20% of disk, 128 GiB)`).
   - Zero-plaintext-key persistence on the provisioning host: `nix run .#provision` generates the testbed's `age` keypair strictly in `/dev/shm` (RAM), updates `config/inventory.nix` and `secrets/.sops.yaml`, re-keys `secrets/secrets.yaml`, embeds the private key into the installer ISO (or deploys over SSH), and `shred`s the key from RAM on exit.

---

## Provisioning & Installation Workflow

### 1. Provision a Testbed on Dev Machine / Cloudtop
Generate a per-testbed `age` key in RAM, register the host in `config/inventory.nix` and `secrets/.sops.yaml`, re-key `secrets/secrets.yaml`, and build (or flash) the custom installer ISO:

```bash
# Prod testbed (default: prata-admin + prata only):
nix run .#provision -- prata-tb-01 --flash /dev/sdX

# Dev testbed (adds developer accounts + Home Manager):
nix run .#provision -- prata-dev-01 --profile dev --flash /dev/sdX

# Or deploy directly over SSH to a live NixOS installer via nixos-anywhere:
nix run .#provision -- prata-tb-01 --target root@<target-ip>
```

To edit encrypted secrets manually:
```bash
sops --config secrets/.sops.yaml secrets/secrets.yaml
```

### 2. Boot Installer Media & Run 1-Step Bare-Metal Install
Boot the target machine from the flashed USB installer and run:
```bash
sudo install-testbed
# Or specify a host explicitly:
sudo install-testbed prata-tb-01
```
`install-testbed` automatically:
1. Formats and mounts the target NVMe disk via `disko` (`ESP` at `/boot`, `ext4` at `/`).
2. Installs the embedded `/etc/sops/age/keys` into `/mnt/var/lib/sops-nix/keys` (`0400`, `root:root`).
3. Runs `nixos-install --flake /etc/prata-nixos#<hostName> --no-root-passwd`.

Reboot into the installed system when complete:
```bash
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
