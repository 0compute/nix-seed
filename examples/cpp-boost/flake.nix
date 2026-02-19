{
  description = "Example C++ project using Boost and nix-zero-setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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
        default = pkgs.stdenv.mkDerivation {
          pname = "cpp-boost-example";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = with pkgs; [
            cmake
            ninja
          ];
          buildInputs = with pkgs; [ boost ];
        };
      in
      {
        packages = {
          inherit default;
          nix-build-container = inputs.nix-zero-setup.lib.mkBuildContainer {
            inherit pkgs;
            name = "cpp-boost-build-env";
            inputsFrom = [ default ];
            contents = with pkgs; [ gcc ];
          };
        };
      }
    );
}
