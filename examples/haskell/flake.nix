{

  # a real, heavy dependency tree: GHC plus pandoc's own closure (its
  # readers, writers, and the ~80 Haskell packages they pull in). zlib
  # is patched non-substitutable so the closure has an actual compile
  # to amortise rather than a cache.nixos.org pull -- the same idea as
  # examples/curl's patched zlib, but reached through the Haskell
  # packages that link it (zip-archive, and pandoc through it) rather
  # than a single C program.

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
          # the HASKELL zlib package, not the C library of the same name:
          # patching pkgs.zlib (as examples/curl does) reaches GHC's own
          # build too -- it links zlib -- and forces a from-scratch GHC
          # compile, tens of minutes, which is what this example is
          # supposed to avoid. haskellPackages.override scopes the patch
          # to one Cabal package instead.
          pkgs = inputs.nixpkgs.legacyPackages.${system}.extend (
            _final: prev: {
              haskellPackages = prev.haskellPackages.override {
                overrides = _hself: hsuper: {
                  zlib = hsuper.zlib.overrideAttrs (previous: {
                    pname = "${previous.pname}-nonsubstitutable";
                    postPatch = (previous.postPatch or "") + ''
                      echo '-- nix-seed benchmark' >>zlib.cabal
                    '';
                  });
                };
              };
            }
          );
        in
        {

          # ghcWithPackages is a buildEnv-style wrapper, not a compile of
          # its own: the closure's size and the caching workflows' real
          # work both come from pandoc's dependency tree, not from this
          # derivation itself.
          default = pkgs.haskellPackages.ghcWithPackages (ps: [ ps.pandoc ]);

          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };

        }
      );
  };

}
