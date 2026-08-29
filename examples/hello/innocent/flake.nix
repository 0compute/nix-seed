{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = ./../../..;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {

    seedCfg.trust = "innocent";

    packages =
      # systems from nixpkgs.lib, not nix-seed: referencing
      # `inputs.nix-seed.inputs` forces nix-seed's whole flake evaluation
      # (mkFlake + every flakeModule), which the seed no longer bakes.
      inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed
        (
          system:
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          in
          {
            default = pkgs.writeScriptBin "hello" ''
              ${pkgs.hello}/bin/hello -g "hello nix-seed"
            '';
            seed = inputs.nix-seed.lib.mkSeed {
              inherit pkgs;
              inherit (inputs) self;
            };
          }
        );

  };

}
