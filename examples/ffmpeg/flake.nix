{

  # a real, substantial C dependency tree: ffmpeg-full pulls in x264,
  # x265, dav1d, opus, freetype, fontconfig and dozens more. x264 is
  # patched non-substitutable so the closure has an actual compile to
  # amortise rather than a cache.nixos.org pull -- the same idea as
  # examples/python's patched zstd, at the scale of a real project's
  # dependency tree instead of one bolted-on library.

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
              # substituted from cache.nixos.org, and ffmpeg-full rebuilds
              # from source behind it, so the caching workflows have a real
              # local build to amortise.
              x264 = prev.x264.overrideAttrs (previous: {
                pname = "${previous.pname}-nonsubstitutable";
                # a leading newline: the upstream postPatch this appends to
                # is not guaranteed to end in one, and gluing onto its last
                # line breaks whatever command that line runs.
                postPatch = (previous.postPatch or "") + ''

                  echo '/* nix-seed benchmark */' >>x264.h
                '';
              });
              # forcing x264 to rebuild also forces ffmpeg-headless (an
              # input of ffmpeg-full) to rebuild, which re-runs its FATE
              # test suite -- normally skipped, since cache.nixos.org
              # ships an already-tested build. fate-seek-hls fails in
              # this sandbox; disabled since correctness of ffmpeg's own
              # tests is not what this example measures.
              ffmpeg-headless = prev.ffmpeg-headless.overrideAttrs (_: {
                doCheck = false;
              });
            }
          );
        in
        {

          default = pkgs.ffmpeg-full;

          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };

        }
      );
  };

}
