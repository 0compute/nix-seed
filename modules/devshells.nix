{ inputs, ... }: {

  imports = [ inputs.devshell.flakeModule ];

  perSystem = { lib, pkgs, ... }: {

    devshells.default = {
      packages =
        with pkgs;
        [
          cosign
          oras
          # bench/: the dependencies bench/pyproject.toml declares; keep
          # both in step
          (python3.withPackages (p: [
            p.matplotlib
            p.pyyaml
            p.typer
          ]))
        ]
        # squashfs is the linux delivery format; darwin ships a disk image
        # built with hdiutil, a system binary rather than a nixpkgs one.
        # see DESIGN.md#delivery.
        ++ lib.optionals stdenv.hostPlatform.isLinux [ squashfsTools ];

      # the bench package runs from its source tree, so edits need no
      # reinstall; the commands mirror pyproject's [project.scripts]
      env = [
        {
          name = "PYTHONPATH";
          eval = "$PRJ_ROOT/bench/src";
        }
      ];
      commands = [
        {
          name = "bench-workflows";
          command = ''python -m bench.workflows "$@"'';
          help = "collect build-* workflow timings into bench/workflows.csv";
        }
        {
          name = "bench-graph";
          command = ''python -m bench.graph "$@"'';
          help = "graph bench/workflows.csv into bench/workflows.svg";
        }
      ];
    };

  };

}
