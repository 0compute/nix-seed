{

  # a real, substantial C dependency tree: imagemagick pulls in libpng,
  # libjpeg, libtiff, libwebp, openjpeg, freetype, fontconfig and more.
  # libpng is patched non-substitutable so the closure has an actual
  # compile to amortise rather than a cache.nixos.org pull -- the same
  # idea as examples/python's patched zstd, at the scale of a real
  # project's dependency tree instead of one bolted-on library.

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
      inputs.nixpkgs.lib.genAttrs inputs.nixpkgs.lib.systems.flakeExposed (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system}.extend (
            _final: prev: {
              # deliberately non-upstream: a patched dependency can never be
              # substituted from cache.nixos.org, and imagemagick rebuilds
              # from source behind it, so the caching workflows have a real
              # local build to amortise.
              libpng = prev.libpng.overrideAttrs (previous: {
                pname = "${previous.pname}-nonsubstitutable";
                # a leading newline: the upstream postPatch this appends to
                # (a bare `patch -Np1` with no trailing newline) would
                # otherwise glue onto this text and corrupt its own flags.
                postPatch = (previous.postPatch or "") + ''

                  echo '/* nix-seed benchmark */' >>png.h
                '';
              });
            }
          );
        in
        {

          default = pkgs.imagemagick;

          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };

        }
      );
  };

}
