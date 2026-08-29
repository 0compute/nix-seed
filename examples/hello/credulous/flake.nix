{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = ./../../..;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs: {

    seedCfg = {
      trust = "credulous";
      builders = {
        github = {
          enable = true;
          master = true;
        };
        gitlab.enable = true;
        scaleway.enable = true;
      };
      quorum = 2;
    };

    packages = inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in
      {
        default = pkgs.hello;
        seed = inputs.nix-seed.lib.mkSeed {
          inherit pkgs;
          inherit (inputs) self;
        };
      }
    );

  };

}
