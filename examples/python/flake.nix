{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = ../..;
      inputs = {
        nixpkgs.follows = "nixpkgs";
        mkdocs-flake.inputs.pyproject-nix.follows = "pyproject-nix";
      };
    };
    pyproject-nix = {
      url = "github:kingarrrt/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {
    packages =
      # systems from nixpkgs.lib, not nix-seed: referencing
      # `inputs.nix-seed.inputs` forces nix-seed's whole flake evaluation
      # (mkFlake + every flakeModule), which the seed no longer bakes.
      inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed
        (
          system:
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            project = inputs.pyproject-nix.lib.project.loadPyproject {
              projectRoot = ./.;
            };
            python = builtins.head (
              inputs.pyproject-nix.lib.util.filterPythonInterpreters {
                inherit (project) requires-python;
                inherit (pkgs) pythonInterpreters;
              }
            );
          in
          {

            default = python.pkgs.buildPythonPackage (
              pkgs.lib.recursiveUpdate (project.renderers.buildPythonPackage {
                inherit python;
              }) { meta.mainProgram = "hello"; }
            );

            seed = inputs.nix-seed.lib.mkSeed {
              inherit pkgs;
              inherit (inputs) self;
            };

          }
        );
  };

}
