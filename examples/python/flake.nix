{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = ../..;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-nix = {
      url = "github:kingarrrt/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs: {
    packages = inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
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
          project.renderers.buildPythonPackage { inherit python; }
        );

        seed = inputs.nix-seed.lib.mkSeed {
          inherit pkgs;
          inherit (inputs) self;
        };

      }
    );
  };

}
