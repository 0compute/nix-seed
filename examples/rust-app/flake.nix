{
  description = "Example Rust project using nix-zero-setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    nix-zero-setup = {
      url = "github:your-org/nix-zero-setup";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-utils.lib.eachSystem (import inputs.systems) (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "rust-app";
          version = "0.1.0";
          src = ./.;
          # in a real project, this would be a hash or a generated file
          cargoLock.lockFile = ./Cargo.lock;
        };
      in
      {
        packages = {
          inherit default;
          nix-build-container = inputs.nix-zero-setup.lib.mkBuildContainer {
            inherit pkgs;
            name = "rust-build-env";
            inputsFrom = [ default ];
            contents = with pkgs; [
              rust-analyzer
              clippy
            ];
          };
        };
      }
    );
}
