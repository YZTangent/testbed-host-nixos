# Declarative Testbed Inventory and Ephemeral Age Key Provisioning

**Status:** accepted

PRATA testbed workstations (<100 benches) require both a frozen, reproducible OS baseline and per-bench identity/secret isolation without a post-install chicken-and-egg rebuild loop. We decided to separate shared Golden OS modules (`modules/`) from a checked-in pure-data testbed inventory (`config/inventory.nix`), and to generate each testbed's `age` private key ephemerally in RAM (`/dev/shm`) during `nix run .#provision`—injecting it directly into the installer ISO (`/etc/sops/age/keys`) or via `nixos-anywhere --extra-files` (`/var/lib/sops-nix/keys`) while committing only the public key to `config/inventory.nix` and `secrets/.sops.yaml`.

## Considered Options

1. **Golden OS modules + `config/inventory.nix` + ephemeral RAM key generation (Chosen):** Preserves 99.99% Nix store cache sharing, keeps `hostname`, `/etc/hosts`, `sudo`, and `nixos-rebuild switch` native, supports offline Digital Twin lookups in Git, decrypts `secrets.yaml` on Boot #1, and leaves zero private keys on the developer machine's disk.
2. **Unversioned runtime identity injection (`networking.hostName = ""`):** Rejected because leaving `hostName` empty in NixOS breaks `system.activationScripts.hostname`, `/etc/hosts` `sudo` resolution, `nixos-rebuild` flake target auto-discovery, and offline Digital Twin configuration lookup in Git.
3. **Post-install SSH host key extraction (`ssh-to-age` after Boot #1):** Rejected because it requires a manual two-pass install-then-rebuild loop for every provisioned or wiped machine.
