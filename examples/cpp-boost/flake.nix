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

        seed = inputs.nix-seed.lib.mkSeed {
          inherit pkgs;
          inherit (inputs) self;
        };

      }
    );
  };

}
