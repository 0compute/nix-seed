{

  description = "Nix CI, Tax-Free. Unbroken Flow.";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emanote = {
      url = "github:srid/emanote";
      inputs = {
        flake-parts.follows = "flake-parts";
        git-hooks.follows = "git-hooks";
        nixpkgs.follows = "nixpkgs";
      };
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    # transitive: poetry2nix
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    github-actions-nix = {
      url = "github:synapdeck/github-actions-nix";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };

    # TODO: implement
    gitlab-ci = {
      url = "git+https://gitlab.horizon-haskell.net/nix/gitlab-ci.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    mkdocs-flake = {
      url = "github:applicative-systems/mkdocs-flake";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        poetry2nix.follows = "poetry2nix";
      };
    };

    # transitive: nix-unit, poetry2nix
    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs = {
        nix-github-actions.follows = "nix-github-actions";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    nix2container = {
      url = "github:roundtablelove/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # transitive: mkdocs-flake, treefmt-nix
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs = {
        flake-utils.follows = "flake-utils";
        nix-github-actions.follows = "nix-github-actions";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    systems.url = "github:nix-systems/default";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {

      imports = [ ./modules ];

      systems = import inputs.systems;

      flake.lib.mkSeed = import ./mkseed { inherit (inputs) nix2container; };

    };

}
