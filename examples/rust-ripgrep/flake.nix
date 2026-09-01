{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    # a real, moderate crate tree built from upstream source (flake = false
    # -> we just want the tree, not its flake outputs).
    ripgrep = {
      url = "github:BurntSushi/ripgrep";
      flake = false;
    };
    nix-seed = {
      url = ./../..;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {
    packages =
      # systems from nixpkgs.lib, not nix-seed: referencing
      # `inputs.nix-seed.inputs` forces nix-seed's whole flake evaluation
      # (mkFlake + every flakeModule), which the seed no longer bakes.
      inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          craneLib = inputs.crane.mkLib pkgs;

          commonArgs = {
            # raw source, not cleanCargoSource: ripgrep's build reads non-.rs
            # files via include_str! (completions, man/help templates) that
            # cleaning would drop.
            src = inputs.ripgrep;
            strictDeps = true;
          };

          # dependencies compiled on their own. baked into the seed via
          # the package's inputDerivation, so the consumer's offline build
          # recompiles only ripgrep itself, not the dep tree.
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          default = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };
        }
      );
  };

}
