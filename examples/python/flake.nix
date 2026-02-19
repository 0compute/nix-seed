{
  description = "Example Python ML project using pyproject.nix and nix-zero-setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-zero-setup = {
      url = "github:your-org/nix-zero-setup";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        python = pkgs.python3;
        pythonEnv = python.withPackages (
          (inputs.pyproject-nix.lib.project.loadPyproject { projectRoot = ./.; })
          .renderers.withPackages
            { inherit python; }
        );
      in
      {
        packages = {
          default = pythonEnv;

          nix-build-container = inputs.nix-zero-setup.lib.mkBuildContainer {
            inherit pkgs;
            name = "ml-build-env";
            inputsFrom = [ pythonEnv ];
            contents = with pkgs; [ hatch ];
          };
        };
      }
    );
}
