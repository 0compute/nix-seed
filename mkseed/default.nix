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
      # packages whose bin/ (and share/, etc.) are unioned into a buildEnv,
      # baked into the seed and reachable at .seed/env -- a single dir with
      # bin/ for the runner's PATH and etc/nix.conf for the build config.
      # its symlinks point into /nix/store, resolved once the seed is
      # mounted. defaults to just nix. NOTE: keep this a curated tool list,
      # not the whole closure -- buildEnv collides on duplicate paths and
      # the closure (already at /nix/store) is full of build-only deps.
      pathPackages ? [ nix ],
      nixConf ? "",
      # squashfs zstd level. 15 is squashfs's default and the knee of the
      # curve: ~3x faster to build than 19 for ~1% more size. drop toward
      # 9 to trade image size for a much faster seed build; the consumer
      # restores from the in-datacenter cache where size barely matters.
      compressionLevel ? 9,
      # flake inputs (by name, at any depth) whose source is NOT baked
      # into the seed: nix-seed's own dev/docs/CI tooling, never needed
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
        "poetry2nix"
        "treefmt-nix"
      ],
      ...
    }@args:
    let

      inherit (pkgs) lib stdenv;
      inherit (stdenv.hostPlatform) system;

      # baked into the seed and written by the consumer as the build's
      # nix.conf: single-user, offline, no substituters/builders/registry
      # so anything that reaches for the network fails fast.
      nixConfText = ''
        experimental-features = nix-command flakes
        build-users-group =
        sandbox = false
        substitute = false
        fallback = false
        substituters =
        trusted-substituters =
        builders =
        flake-registry =
        connect-timeout = 1
        download-attempts = 1
        show-trace = true
        eval-cache = false
        ${nixConf}
      '';

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
      # inputDerivation is taken (which would recurse into this seed's own
      # closure); selfFilter is the value-level predicate.
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

      # a buildEnv unioning pathPackages' bin/ plus nix.conf at etc/nix.conf,
      # baked into the seed and exposed at .seed/env: .seed/env/bin for PATH,
      # .seed/env/etc/nix.conf for the offline build config.
      pathEnv = pkgs.buildEnv {
        name = "${name}-env";
        paths = pathPackages ++ [
          (pkgs.writeTextDir "etc/nix.conf" nixConfText)
        ];
      };

      # every store path the seed must contain, as closureInfo rootPaths:
      #   - nix itself: the consumer runs it from the mounted store.
      #   - pathEnv: the buildEnv exposed at .seed/env (bin/ + etc/nix.conf).
      #   - every flake input source, recursively -> offline flake
      #     *evaluation* (nix reads each locked input from the store).
      #   - each output's inputDerivation -> its full build-input closure,
      #     so `nix build` runs offline without rebuilding stdenv/glibc.
      rootPaths = [
        nix
        pathEnv
      ]
      ++ (
        let
          collect =
            flake:
            lib.concatMap (i: [ i ] ++ collect i) (
              lib.attrValues (removeAttrs (flake.inputs or { }) excludeInputs)
            );
        in
        map (i: i.outPath) (collect self)
      )
      ++ lib.filter (p: p != null) (
        map (
          drv:
          tryWarn "no build closure for a flake output (threw)" null (
            drv.inputDerivation or drv
          )
        ) selfDrvs
      );

      closure = pkgs.closureInfo { rootPaths = rootPaths; };

      # the seed: a squashfs of the build closure the consumer mounts as
      # /nix/store (store paths sit at the fs root, basename = store
      # hash-name). under .seed/ (so the squashfs is the seed's only
      # artifact) it also carries `registration` (to re-populate a fresh
      # nix db offline, marking the baked paths valid) and an `env` symlink
      # into the baked buildEnv (env/bin for PATH, env/etc/nix.conf for the
      # build config). the consumer reads them from the read-only mount.
      # mounting is O(1); reads decompress lazily, so there is no per-file
      # extraction. see DESIGN.md#delivery.
      seedFs =
        pkgs.runCommand "${name}"
          {
            nativeBuildInputs = [ pkgs.squashfsTools ];
            passthru = {
              inherit name tag pathEnv;
              nixConf = nixConfText;
              # marker so a seed harvesting self.packages skips a nested
              # seed (its inputDerivation would recurse into this closure).
              isNixSeed = true;
            };
          }
          ''
            mkdir $out
            # timestamps come from SOURCE_DATE_EPOCH (set by nix) for a
            # reproducible image; passing -*-time here would conflict.
            # registration + env go under .seed/ as pseudo-entries so the
            # squashfs is the only output. mksquashfs clamps pseudo mtimes to
            # SOURCE_DATE_EPOCH too, so the image stays reproducible.
            # .seed/env -> the baked buildEnv, resolved through the mounted
            # store; the consumer adds /nix/.ro-store/.seed/env/bin to PATH
            # and reads /nix/.ro-store/.seed/env/etc/nix.conf.
            mksquashfs $(cat ${closure}/store-paths) $out/store.squashfs \
              -keep-as-directory -all-root -no-hardlinks \
              -comp zstd -Xcompression-level ${toString compressionLevel} \
              -p '.seed d 555 0 0' \
              -p ".seed/registration f 444 0 0 cat ${closure}/registration" \
              -p ".seed/env s 777 0 0 ${pathEnv}"
          '';
    in
    # nix-seed is Linux only. the consumer mounts the squashfs as
    # /nix/store and overlays a writable upper for build output; macOS has
    # neither loop-mounts nor overlayfs. fail here rather than producing a
    # seed nothing can run. see DESIGN.md#constraints.
    lib.throwIf (!stdenv.hostPlatform.isLinux) ''
      mkSeed: unsupported system "${system}". nix-seed is Linux only;
      see DESIGN.md#constraints and DESIGN.md#macos.
    '' seedFs;
in
mkSeed
