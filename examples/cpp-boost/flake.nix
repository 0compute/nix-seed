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
          rec {

            # deliberately non-upstream: a patched dependency can never be
            # substituted from cache.nixos.org, so the caching workflows
            # have a real local build to amortise
            expensive = pkgs.zstd.overrideAttrs (previous: {
              pname = "${previous.pname}-nonsubstitutable";
              postPatch = (previous.postPatch or "") + ''
                echo '/* nix-seed benchmark */' >>lib/zstd.h
              '';
            });

            default = pkgs.stdenv.mkDerivation {
              pname = "cpp-boost-example";
              version = "0.1.0";
              src = ./.;
              nativeBuildInputs = with pkgs; [
                cmake
                ninja
              ];
              buildInputs = [
                pkgs.boost
                expensive
              ];
            };

            seed = inputs.nix-seed.lib.mkSeed {
              inherit pkgs;
              inherit (inputs) self;
            };

          }
        );
  };

}
