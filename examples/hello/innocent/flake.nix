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
      inputs.nixpkgs.lib.genAttrs (import inputs.nix-seed.inputs.systems)
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
