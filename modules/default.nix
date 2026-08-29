{

  imports = [
    ./apps.nix
    ./checks.nix
    ./devshells.nix
    ./docs.nix
    # TODO: https://flake.parts/options/files.html
    # ./files.nix
    ./githubactions.nix
    ./hooks.nix
    # ./nixunit.nix
    ./packages.nix
    ./seedcfg.nix
    ./builders.nix
  ];

}
