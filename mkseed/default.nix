{ nix2container }:
let
  mkSeed =
    {
      pkgs,
      self,
      # drop a harvested derivation by value (forces it).
      selfFilter ? (_drv: true),
      # drop a harvested output by attribute NAME, before its value is
      # forced. Needed for outputs that fail to *evaluate* (a builtin
      # type error tryEval cannot catch, e.g. emanote's docs), which must
      # be skipped without ever forcing them.
      selfFilterName ? (_name: true),
      # name from flake default package
      name ?
        let
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        "${package.pname or package.name or "unnamed"}.seed",
      tag ? self.rev or self.dirtyRev or null,
      nix ? pkgs.nixVersions.latest,
      nixConf ? "",
      # flake inputs (by name, at any depth) whose source is NOT baked
      # into the image: nix-seed's own dev/docs/CI tooling, never needed
      # to build a consumer's project. removeAttrs also stops the collect
      # recursion into them, dropping their whole subtree (e.g. emanote's
      # haskell closure).
      excludeInputs ? [
        "devshell"
        "emanote"
        "git-hooks"
        "github-actions-nix"
        "gitlab-ci"
        "mkdocs-flake"
        "nix-github-actions"
        "nix-unit"
        "nix2container"
        "poetry2nix"
        "treefmt-nix"
      ],
      # TODO: hook in seedCfg
      githubRunner ? false,
      ...
    }@args:
    let

      inherit (pkgs) lib stdenv;
      inherit (stdenv.hostPlatform) system;

      config = lib.recursiveUpdate {
        Entrypoint = [
          (pkgs.writeShellScript "entrypoint" ''
            ${lib.optionalString (!githubRunner) ''
              # offline contract: refuse to run with network access.
              # (githubRunner images are exempt: the actions runtime must
              # reach GitHub; there the nix sandbox isolates builds.)
              for i in /sys/class/net/*; do
                [[ -e $i ]] || continue
                [[ ''${i##*/} == lo ]] || {
                  echo "seed: network present; run with --network none" >&2
                  exit 1
                }
              done
            ''}
            (($#)) || set -- /bin/sh
            exec "$@"
          '')
        ];
        Env = lib.mapAttrsToList (name: value: "${name}=${value}") (
          {
            # nix derives its cache dir from HOME; unset yields a relative
            # ".cache/nix" path and fails inside the container.
            HOME = "/tmp";
          }
          # actions runtime loads glibc/libstdc++ from the multiarch path
          # populated by the githubRunner setup derivation
          // lib.optionalAttrs githubRunner {
            LD_LIBRARY_PATH =
              "/lib:/lib64:/lib/" + stdenv.hostPlatform.linuxArch + "-linux-gnu";
          }
        );
      } args.config or { };

      corePkgs = [
        # nix from args
        nix
      ]
      ++ (with pkgs; [
        busybox # debug helper
        (writeTextDir "etc/nix/nix.conf" ''
          experimental-features = nix-command flakes
          # single-user mode: builds run as root in the container, so
          # disable the build-users mechanism
          build-users-group =
          sandbox = false
          # post-build-hook = ${./post-build-hook}
          # no sub, no fallback, build can only happen here
          substitute = false
          fallback = false
          # belt-and-braces offline: nothing to substitute from, no
          # remote builders, no global flake-registry fetch for unlocked
          # refs; anything that still tries the network fails fast
          substituters =
          trusted-substituters =
          builders =
          flake-registry =
          connect-timeout = 1
          download-attempts = 1
          show-trace = true
          eval-cache = false
          ${nixConf}
        '')
      ]);

      # tryEval with a warning + fallback on throw. Catches assert/throw
      # only; outputs failing with builtin type errors (which tryEval
      # cannot catch) must be dropped by selfFilterName, before they are
      # forced at all.
      tryWarn =
        msg: fallback: x:
        let
          r = builtins.tryEval x;
        in
        if r.success then r.value else lib.warn "mkSeed: ${msg}" fallback;

      # keep a harvested candidate. isDerivation reads only `.type`
      # (cheap); the isNixSeed guard drops a nested seed before its
      # inputDerivation is taken (which would recurse image -> contents
      # -> seedClosure -> inputDerivation); selfFilter is the value-level
      # predicate.
      keepDrv =
        drv:
        tryWarn "skipping a flake output that threw during evaluation" false (
          lib.isDerivation drv && !(drv.isNixSeed or false) && selfFilter drv
        );

      # derivations the consumer flake exposes.
      selfDrvs =
        let
          outputs =
            attr:
            lib.attrValues (
              lib.filterAttrs (name: _: selfFilterName name) (
                self.${attr}.${system} or { }
              )
            );
        in
        lib.filter keepDrv (
          # apps have { type = "app"; program = "..."; }.
          map (app: app.package or null) (outputs "apps")
          ++ lib.concatMap outputs [
            "checks"
            "devShells"
            "packages"
          ]
        );

      # store paths forced into the image closure by *listing* them in a
      # file, so Nix's reference scanner pulls each path and its whole
      # closure into the image (buildEnv would drop them — it only links
      # /bin,/etc,/lib, and the inputDerivation stub links nothing). Two
      # groups:
      #   - every flake input source, recursively -> offline flake
      #     *evaluation* (nix reads each locked input from the store).
      #   - each harvested derivation's inputDerivation -> its full
      #     build-input closure, so `nix build` runs offline without
      #     rebuilding stdenv/glibc/etc. from source.
      seedClosure = pkgs.writeTextDir "etc/nix-seed/closure" (
        lib.concatStringsSep "\n" (
          let
            collect =
              flake:
              lib.concatMap (i: [ i ] ++ collect i) (
                lib.attrValues (removeAttrs (flake.inputs or { }) excludeInputs)
              );
          in
          lib.unique (
            map (i: i.outPath) (collect self)
            ++ lib.filter (p: p != null) (
              map (
                drv:
                tryWarn "no build closure for a flake output (threw)" null
                  (drv.inputDerivation or drv).outPath
              ) selfDrvs
            )
          )
        )
      );

      contents =
        # GHA runner hacks
        lib.optionals githubRunner (
          with pkgs;
          [
            stdenv.cc.cc.lib
            glibc
            nodejs
            (runCommand "setup" { } ''
              mkdir $out
              cd $out

              # actions runtime expects glibc libs at the multiarch path
              multiarchDir=lib/${stdenv.hostPlatform.linuxArch}-linux-gnu
              mkdir -p $multiarchDir
              ln -s ${glibc}/lib/libc.so.6 $multiarchDir
              ln -s ${stdenv.cc.cc.lib}/lib/libstdc++.so.6 $multiarchDir

              # TOGO: no longer needed I think
              externals=__e
              mkdir $externals
              ln -s ${nodejs} $externals/node${lib.versions.major nodejs.version}
            '')
          ]
        )
        ++ corePkgs
        # runtime tools on /bin (PATH) for the harvested derivations.
        ++ lib.concatMap (
          drv:
          lib.concatMap (attr: drv.${attr} or [ ]) [
            "buildInputs"
            "nativeBuildInputs"
            "propagatedBuildInputs"
            "propagatedNativeBuildInputs"
          ]
        ) selfDrvs
        ++ [ seedClosure ]
        ++ args.contents or [ ];

      root = pkgs.buildEnv {
        name = "root";
        paths = contents;
        pathsToLink = [
          "/bin"
          "/etc"
          "/lib"
        ]
        ++ lib.optionals githubRunner [ "/__e" ];
        ignoreCollisions = true;
      };

      # the seed's trust anchor: every store path in the image closure
      # paired with its NAR hash, sorted. two honest builders can realise
      # identical store paths and still differ on the image digest (layer
      # compression, manifest serialisation), which reads as a quorum
      # failure on a build that in fact reproduced. NAR hashes are what
      # nix guarantees, so they are what builders compare. derived from
      # `root` rather than `contents` so it describes what the image
      # holds, not what it was asked to hold.
      # see DESIGN.md#closure-manifest.
      manifest =
        pkgs.runCommand "${name}-manifest"
          {
            __structuredAttrs = true;
            exportReferencesGraph.closure = [ root ];
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            jq --raw-output '.closure[] | "\(.narHash)  \(.path)"' \
              "$NIX_ATTRS_JSON_FILE" |
              LC_ALL=C sort >"$out"
          '';

      # squashfs delivery variant: the same closure as the OCI image
      # (`root`), packed into a read-only fs the consumer mounts instead
      # of extracting. store paths sit at the squashfs root (basename =
      # store hash-name), so mounting it AS /nix/store yields the real
      # paths. `registration` re-populates a fresh nix db offline so the
      # baked paths count as valid. see DESIGN.md#macos, squashfs design.
      seedFs =
        pkgs.runCommand "${name}-fs"
          {
            nativeBuildInputs = [ pkgs.squashfsTools ];
            ci = pkgs.closureInfo { rootPaths = [ root ]; };
          }
          ''
            mkdir $out
            # timestamps come from SOURCE_DATE_EPOCH (set by nix) for a
            # reproducible image; passing -*-time here would conflict.
            mksquashfs $(cat $ci/store-paths) $out/store.squashfs \
              -keep-as-directory -all-root -no-hardlinks \
              -comp zstd -Xcompression-level 19
            cp $ci/registration $out/registration
          '';

      image = nix2container.packages.${system}.nix2container.buildImage (
        # defaults, overridable via extra mkSeed args
        {
          maxLayers = 50;
          initializeNixDatabase = true;
        }
        // (lib.removeAttrs args (
          (builtins.attrNames (builtins.functionArgs mkSeed))
          ++ [
            "config"
            "contents"
          ]
        ))
        // {
          inherit config name tag;
          copyToRoot = [ root ];
        }
      );
    in
    # nix-seed is Linux only. the seed is an OCI image the build runs
    # inside, which needs a container runtime to mount it and an overlay
    # to capture build output; macOS has neither. fail here rather than
    # producing an image nothing can run. see DESIGN.md#constraints.
    lib.throwIf (!stdenv.hostPlatform.isLinux) ''
      mkSeed: unsupported system "${system}". nix-seed is Linux only;
      see DESIGN.md#constraints and DESIGN.md#macos.
    ''
      # expose metadata for unit testing and inspection. buildLayeredImage does
      # not support passthru or automatically export its internal arguments
      (
        image
        // {
          inherit
            name
            tag
            contents
            config
            corePkgs
            root
            manifest
            seedFs
            ;
          fs = seedFs;
          # marker so a seed harvesting self.packages skips a nested seed
          # (its inputDerivation would recurse through seedClosure).
          isNixSeed = true;
        }
      );
in
mkSeed
