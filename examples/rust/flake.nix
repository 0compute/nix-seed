{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = "github:your-org/nix-seed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs: {
    packages = inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
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
