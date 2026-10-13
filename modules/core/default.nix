{ ... }:

{
  imports = [
    ./packages.nix
    ./network.nix
    ./users.nix
    ./nix-ld.nix
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
