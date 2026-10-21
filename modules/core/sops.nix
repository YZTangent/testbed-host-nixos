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
