{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
      inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed
        (
          system:
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          in
          {

            default = pkgs.rustPlatform.buildRustPackage {
              pname = "rust-app";
              version = "0.1.0";
              src = ./.;
              # in a real project, this would be a hash or a generated file
              cargoLock.lockFile = ./Cargo.lock;
            };

            seed = inputs.nix-seed.lib.mkSeed {
              inherit pkgs;
              inherit (inputs) self;
            };

          }
        );
  };

}
