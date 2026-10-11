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
}
