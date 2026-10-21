# PRATA NixOS Testbed Architecture

## Overview

This repository defines the declarative NixOS operating system, hardware drivers, GROD inference environment, and provisioning pipeline for PRATA B850 + RTX 5090 robotics testbed workstations.

## Core Design Principles

1. **Golden OS Modules + Checked-In Data Inventory (`config/inventory.nix`):**
   - All OS modules (`modules/`) are shared identically across every testbed machine (99.99% shared `/nix/store` closure).
   - Per-testbed identity (`hostName`), build profile (`profile`: `"prod"` or `"dev"`), target NVMe device (`diskDevice`), swap overrides (`swap`), and public key (`agePublicKey`) are tracked as pure data in `config/inventory.nix`.
2. **Prod vs. Dev Testbed Profiles (`prata.profile`):**
   - `prod` testbeds provision only `prata-admin` (privileged: `wheel`, `networkmanager`, `docker`, `video`) and `prata` (unprivileged: `networkmanager`, `docker`, `video`) without Home Manager.
   - `dev` testbeds additionally provision developer accounts (`prata.devUsers`: `tanyuanzheng`, `jiehao`, `zhin`, `danielkun`) managed with Home Manager (`home/default.nix`).
3. **Ephemeral-First Secret Provisioning (`provision-testbed` & `install-testbed`):**
   - Each testbed has a dedicated `age` key stored at `/var/lib/sops-nix/keys` (`0400 root:root`) on the target machine.
   - `provision-testbed` runs on the developer/cloudtop machine, generates the testbed's `age` keypair in RAM (`/dev/shm`), registers the public key in `config/inventory.nix` and `secrets/.sops.yaml`, re-encrypts `secrets/secrets.yaml`, and either encrypts the private key in RAM with a One-Time PIN (`keys.age`)—shredding the plaintext private key before `nix build --impure .#iso` embeds `/etc/sops/age/keys.age` into the installer ISO—or pushes it over SSH via `nixos-anywhere --extra-files` before wiping `/dev/shm`.
   - `install-testbed` runs on the bare-metal machine booted from the USB ISO, partitioning the disk via `disko`, prompting for the One-Time PIN to decrypt `/etc/sops/age/keys.age` into `/mnt/var/lib/sops-nix/keys`, and installing `.#<hostName>` so secrets decrypt on first boot.
4. **Declarative Disk (`disko`) & Dynamic Swap (`prata.swap`):**
   - `modules/core/disko.nix` defines a GPT layout with a `1024MiB` `vfat` ESP (`/boot`) and `100%` `ext4` root (`/`).
   - `modules/core/swap.nix` provisions `/var/swapfile` at boot sized to $\min(\lfloor \text{diskPercent} \times \text{disk\_bytes} \rfloor, \text{maxSizeGiB})$ (default `20%`, capped at `128 GiB`).

## Known Tech Debt & Future Optimizations

### Installer ISO Build Time (`nix-store.squashfs` Cache Invalidation & Compression Level)

- **Symptom:** Running `nix run .#provision -- <hostName>` takes ~16–21 minutes to build the installer ISO on each invocation.
- **Root Cause:**
  1. NixOS's `installation-cd-minimal.nix` defaults `isoImage.squashfsCompression` to `"zstd -Xcompression-level 19"`. Compressing the Live USB's `/nix/store` closure (which includes the Live OS kernel and `linux-firmware` blobs needed to initialize NICs/storage on bare metal) at `zstd` level 19 takes ~16 minutes in `mksquashfs`.
  2. In `modules/installer/iso.nix`, per-host provisioning artifacts (`keys.age`, `target-host`, and `prata-nixos`) are currently placed in `environment.etc`. Because `environment.etc` is part of `config.system.build.toplevel` (which lives *inside* `nix-store.squashfs`), every `nix run .#provision -- <hostName>` invalidates `nix-store.squashfs` and forces `mksquashfs` to re-compress the entire Live USB OS closure from scratch.
- **Planned Fix:**
  1. Lower `isoImage.squashfsCompression = "zstd -Xcompression-level 6";` in `modules/installer/iso.nix` (cuts cold `mksquashfs` time from ~16 minutes to ~25 seconds).
  2. Move `keys.age`, `target-host`, and `prata-nixos` out of `environment.etc` and into `isoImage.contents` (mounted at `/iso/...` on the Live USB), updating `install-testbed` and `/etc/motd` to read from `/iso/...`. Because `isoImage.contents` is written directly into the outer ISO9660 filesystem by `xorriso` *outside* `nix-store.squashfs`, the Live USB OS (`nix-store.squashfs`) is built **once** and cached in `/nix/store`, reducing subsequent `nix run .#provision -- <hostName>` ISO builds to **~5 seconds**.
