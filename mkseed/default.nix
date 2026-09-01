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

      # every store path the seed must contain, as closureInfo rootPaths:
      #   - nix itself: the consumer runs it from the mounted store.
      #   - every flake input source, recursively -> offline flake
      #     *evaluation* (nix reads each locked input from the store).
      #   - each output's inputDerivation -> its full build-input closure,
      #     so `nix build` runs offline without rebuilding stdenv/glibc.
      rootPaths =
        [ nix ]
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
            drv: tryWarn "no build closure for a flake output (threw)" null (drv.inputDerivation or drv)
          ) selfDrvs
        );

      closure = pkgs.closureInfo { rootPaths = rootPaths; };

      # the seed: a squashfs of the build closure the consumer mounts as
      # /nix/store (store paths sit at the fs root, basename = store
      # hash-name), plus `registration` to re-populate a fresh nix db
      # offline (marking the baked paths valid) and `nix.conf`. mounting
      # is O(1); reads decompress lazily, so there is no per-file
      # extraction. see DESIGN.md#delivery.
      seedFs =
        pkgs.runCommand "${name}"
          {
            nativeBuildInputs = [
              pkgs.erofs-utils
              pkgs.gnutar
            ];
            passthru = {
              inherit name tag;
              nixConf = nixConfText;
              # marker so a seed harvesting self.packages skips a nested
              # seed (its inputDerivation would recurse into this closure).
              isNixSeed = true;
            };
          }
          ''
            mkdir $out
            # mkfs.erofs packs a tree/tarball, not a path list, so tar the
            # closure with entries rooted at the store hash-name (tar -C
            # /nix/store) -> mounting the image AS /nix/store yields the
            # real paths. timestamps come from SOURCE_DATE_EPOCH (nix).
            tar -C /nix/store -c --owner=0 --group=0 --numeric-owner \
              $(sed 's|^/nix/store/||' ${closure}/store-paths) >closure.tar
            # -C: big compression clusters + tail/fragment packing so the
            # zstd ratio is competitive with squashfs's 128K blocks.
            mkfs.erofs -zzstd,level=19 -C1048576 -Eztailpacking,fragments \
              --all-root --tar=f $out/store.erofs closure.tar
            cp ${closure}/registration $out/registration
            cp ${pkgs.writeText "nix.conf" nixConfText} $out/nix.conf
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
