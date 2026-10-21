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
   - `provision-testbed` runs on the developer/cloudtop machine, generates the testbed's `age` keypair in RAM (`/dev/shm`), registers the public key in `config/inventory.nix` and `secrets/.sops.yaml`, re-encrypts `secrets/secrets.yaml`, and either bakes the private key into the installer ISO (`/etc/sops/age/keys`) or pushes it over SSH via `nixos-anywhere --extra-files` before wiping `/dev/shm`.
   - `install-testbed` runs on the bare-metal machine booted from the USB ISO, partitioning the disk via `disko`, copying `/etc/sops/age/keys` to `/mnt/var/lib/sops-nix/keys`, and installing `.#<hostName>` so secrets decrypt on first boot.
4. **Declarative Disk (`disko`) & Dynamic Swap (`prata.swap`):**
   - `modules/core/disko.nix` defines a GPT layout with a `1024MiB` `vfat` ESP (`/boot`) and `100%` `ext4` root (`/`).
   - `modules/core/swap.nix` provisions `/var/swapfile` at boot sized to $\min(\lfloor \text{diskPercent} \times \text{disk\_bytes} \rfloor, \text{maxSizeGiB})$ (default `20%`, capped at `128 GiB`).
