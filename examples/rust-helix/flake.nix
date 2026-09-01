{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    # a large workspace: the heavy end of the benchmark. built from
    # upstream source (flake = false -> just the tree).
    helix = {
      url = "github:helix-editor/helix";
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
            # raw source, not cleanCargoSource: helix's build reads non-.rs
            # files (languages.toml, runtime/) that cleaning would drop.
            src = inputs.helix;
            strictDeps = true;
            # helix's root is a virtual workspace (no root package), so
            # crane can't infer these.
            pname = "helix";
            version = "unstable";
            # tree-sitter grammars are fetched/compiled at runtime by
            # `hx --grammar build`, not during `cargo build`; keep that off
            # so the build stays offline and hermetic.
            HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "1";
          };

          # dependencies compiled on their own, baked into the seed via the
          # package's inputDerivation; the offline build recompiles only the
          # helix workspace crates, not the (large) dep tree.
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
