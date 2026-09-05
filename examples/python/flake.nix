{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = ../..;
      inputs = {
        nixpkgs.follows = "nixpkgs";
        mkdocs-flake.inputs.pyproject-nix.follows = "pyproject-nix";
      };
    };
    pyproject-nix = {
      url = "github:kingarrrt/pyproject.nix";
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
            project = inputs.pyproject-nix.lib.project.loadPyproject {
              projectRoot = ./.;
            };
            python = builtins.head (
              inputs.pyproject-nix.lib.util.filterPythonInterpreters {
                inherit (project) requires-python;
                inherit (pkgs) pythonInterpreters;
              }
            );
            # python312, not `python` (3.14, the project's own interpreter):
            # pyarrow and torch turned out not yet cached for 3.14 at this
            # nixpkgs revision; 3.12 is established enough to be fully
            # cached for everything below. `heavy` has no functional link
            # to the project, so it doesn't need to match its interpreter.
            #
            # every package here is left unmodified and fully substituted,
            # unlike `default`'s patched zstd: a qhull override (matplotlib
            # and scipy both link it, tried first) forced scipy to rebuild,
            # and scipy's meson build runs its own test suite unconditionally
            # as part of the build itself -- not gated by doCheck, and tens
            # of minutes long. `default`'s zstd override already gives this
            # example a real forced build; `heavy` exists for closure size.
            heavyPkgs = pkgs.python312Packages;
            # deliberately non-upstream: a patched dependency can never be
            # substituted from cache.nixos.org, so the caching workflows
            # have a real local build to amortise. let-bound, not exported:
            # a package attr would make mkSeed bake its *build* closure
            # (cmake, zstd src) into the seed, which the consumer -- who
            # only links the prebuilt outputs -- never needs.
            expensive = pkgs.zstd.overrideAttrs (previous: {
              pname = "${previous.pname}-nonsubstitutable";
              postPatch = (previous.postPatch or "") + ''
                echo '/* nix-seed benchmark */' >>lib/zstd.h
              '';
            });
          in
          {

            default =
              (python.pkgs.buildPythonPackage (
                pkgs.lib.recursiveUpdate (project.renderers.buildPythonPackage {
                  inherit python;
                }) { meta.mainProgram = "hello"; }
              )).overrideAttrs
                (previous: {
                  buildInputs = (previous.buildInputs or [ ]) ++ [ expensive ];
                });

            # a heavier real-world stack alongside the hello-world default:
            # numpy/scipy need BLAS, LAPACK and gfortran's runtime,
            # matplotlib and Pillow need freetype/libjpeg/libtiff/libwebp,
            # numba needs LLVM via llvmlite, pyarrow/opencv4 add their own
            # sizeable C++ libraries. mkSeed harvests every package by
            # default, so this rides in the same seed as default. measured
            # (dry run, all fully substituted): 2.0 GiB.
            heavy = pkgs.python312.withPackages (_: [
              heavyPkgs.numpy
              heavyPkgs.scipy
              heavyPkgs.pandas
              heavyPkgs.matplotlib
              heavyPkgs.scikit-learn
              heavyPkgs.pillow
              heavyPkgs.numba
              heavyPkgs.pyarrow
              heavyPkgs.polars
              heavyPkgs.opencv4
              heavyPkgs.sympy
            ]);

            seed = inputs.nix-seed.lib.mkSeed {
              inherit pkgs;
              inherit (inputs) self;
            };

          }
        );
  };

}
