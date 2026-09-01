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
          (pkgs.writeTextDir "etc/nix/nix.conf" ''
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
            # upstream default is max-jobs = 1, which serializes independent
            # derivations; the runner is dedicated, so use every core.
            max-jobs = auto
            cores = 0
            # ephemeral CI store: skipping sqlite fsyncs speeds --load-db
            # and post-build registration; durability is worthless here.
            fsync-metadata = false
            ${nixConf}
          '')
        ];
      };

      # every store path the seed must contain, as closureInfo rootPaths:
      #   - nix itself: the consumer runs it from the mounted store.
      #   - pathEnv: the buildEnv exposed at .seed/env (bin/ + etc/nix.conf).
      #   - "sources": every flake input source, recursively -> offline
      #     flake *evaluation* (nix reads each locked input from the store).
      #   - each output's inputDerivation -> its full build-input closure,
      #     so the build runs offline without rebuilding stdenv/glibc.
      rootPathsFor =
        bake:
        [
          nix
          pathEnv
        ]
      ++ lib.optionals (lib.elem "sources" bake) (
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

      closureFor = bake: pkgs.closureInfo { rootPaths = rootPathsFor bake; };

      # ---- "drvs" mode: recipe collection (doc/drv-seeds.md) ----
      # collected at EVAL time by reading the .drv files this very eval
      # instantiated -- closureInfo/exportReferencesGraph over a drv
      # demands the full build-time OUTPUT closure (spike finding), so the
      # recipe set is walked here instead and rooted as plain path inputs.

      # store-path lexer over drv ATerm text
      pathRe = "(${builtins.storeDir}/[a-z0-9]{32}-[0-9a-zA-Z+._?=-]+)";
      pathsIn =
        text:
        lib.unique (
          lib.concatMap (m: lib.optional (lib.isList m) (lib.head m)) (
            builtins.split pathRe text
          )
        );
      # inputSrcs = the third bracket group of Derive(...): after the
      # second "],[", up to the next "],\"". env comes last, so any
      # "],[" inside env values cannot shift these two boundaries.
      srcsOf =
        text:
        pathsIn (
          lib.head (
            builtins.split "],\"" (lib.elemAt (builtins.split "],\\[" text) 4)
          )
        );

      # transitive drv-file closure of the harvested outputs
      recipeDrvs = map (n: n.key) (
        builtins.genericClosure {
          startSet = map (drv: {
            key = builtins.unsafeDiscardStringContext drv.drvPath;
          }) selfDrvs;
          operator =
            n:
            map (p: { key = p; }) (
              lib.filter (lib.hasSuffix ".drv") (pathsIn (builtins.readFile n.key))
            );
        }
      );
      # per-drv reference lists: exactly what the consumer db must record
      recipeGraph = map (
        d:
        let
          text = builtins.readFile d;
        in
        {
          drv = d;
          inputDrvs = lib.filter (lib.hasSuffix ".drv") (pathsIn text);
          inputSrcs = srcsOf text;
        }
      ) recipeDrvs;
      # every recipe file as a plain path input of the seed derivation
      recipeRoots = lib.unique (
        lib.concatMap (
          n: map (p: builtins.appendContext p { ${p} = { path = true; }; }) ([ n.drv ] ++ n.inputSrcs)
        ) recipeGraph
      );

      # entry point for the consumer's zero-eval realise path, plus graft
      # metadata: the target's src and the eval-frozen metadata files a
      # graft must refuse to paper over. path STRINGS only -- the files
      # ride via recipeRoots.
      drvManifestFor =
        bake:
        let
          target = self.packages.${system}.default or null;
        in
        pkgs.writeText "drvs.json" (
          builtins.toJSON {
            inherit bake;
            default =
              if target == null then
                null
              else
                {
                  drv = builtins.unsafeDiscardStringContext target.drvPath;
                }
                // lib.optionalAttrs (target ? src) {
                  src = builtins.unsafeDiscardStringContext (toString target.src);
                  srcName = target.src.name or "source";
                };
          }
        );

      # the seed: a squashfs of the build closure the consumer mounts as
      # /nix/store (store paths sit at the fs root, basename = store
      # hash-name). under .seed/ (so the squashfs is the seed's only
      # artifact) it also carries `registration` (to re-populate a fresh
      # nix db offline, marking the baked paths valid) and an `env` symlink
      # into the baked buildEnv (env/bin for PATH, env/etc/nix.conf for the
      # build config). the consumer reads them from the read-only mount.
      # mounting is O(1); reads decompress lazily, so there is no per-file
      # extraction. see DESIGN.md#delivery.
      # one seed, two consumer contracts (doc/drv-seeds.md), selected by
      # attribute rather than argument:
      #   .sources (the default) -- every flake input source baked; the
      #     consumer runs `nix build ./dir`, proving offline *evaluation*.
      #   .drvs -- the instantiated recipes baked instead; the consumer
      #     realises them with zero evaluation and no nixpkgs in the blob.
      mkVariant =
        bake:
        let
          drvsMode = lib.elem "drvs" bake;
          closure = closureFor bake;
          drvManifest = drvManifestFor bake;
        in
        pkgs.runCommand "${name}"
          (
            {
              nativeBuildInputs = [ pkgs.squashfsTools ];
              passthru = {
                inherit name tag pathEnv;
                # marker so a seed harvesting self.packages skips a nested
                # seed (its inputDerivation would recurse into this closure).
                isNixSeed = true;
                # the mode variants, cross-linked so either is reachable
                # from whichever the consumer flake exposes.
                sources = sourcesSeed;
                drvs = drvsSeed;
              };
            }
            // lib.optionalAttrs drvsMode {
              nativeBuildInputs = [
                pkgs.squashfsTools
                pkgs.jq
                nix
              ];
              # every recipe file (drvs + inputSrcs), space-joined; the
              # appendContext path contexts make them plain inputs.
              recipePaths = lib.concatStringsSep " " recipeRoots;
              recipeGraph = builtins.toJSON recipeGraph;
              passAsFile = [
                "recipePaths"
                "recipeGraph"
              ];
              NIX_CONFIG = "experimental-features = nix-command";
            }
          )
          ''
            mkdir $out
            ${lib.optionalString drvsMode ''
              # registration for the recipe files, mirroring closureInfo's
              # record layout: path, narHash (SRI), narSize, deriver
              # (empty), nrefs, refs. drvs carry their true reference
              # lists (walked at eval); srcs are leaves.
              reg() {
                local p=$1
                shift
                printf '%s\n' "$p" \
                  "sha256:$(nix-hash --type sha256 --base32 "$p")" \
                  "$(nix-store --dump "$p" | wc -c)" "" "$#"
                (($# == 0)) || printf '%s\n' "$@"
              }
              {
                cat ${closure}/registration
                while read -r node; do
                  d=$(jq -r .drv <<<"$node")
                  mapfile -t refs < <(jq -r '.inputDrvs[],.inputSrcs[]' <<<"$node")
                  reg "$d" "''${refs[@]}"
                done < <(jq -c '.[]' "$recipeGraphPath")
                while read -r s; do reg "$s"; done \
                  < <(jq -r '.[].inputSrcs[]' "$recipeGraphPath" | sort -u)
              } >recipe-registration
            ''}
            # timestamps come from SOURCE_DATE_EPOCH (set by nix) for a
            # reproducible image; passing -*-time here would conflict.
            # registration + env go under .seed/ as pseudo-entries so the
            # squashfs is the only output. mksquashfs clamps pseudo mtimes to
            # SOURCE_DATE_EPOCH too, so the image stays reproducible.
            # .seed/env -> the baked buildEnv, resolved through the mounted
            # store; the consumer adds /nix/.ro-store/.seed/env/bin to PATH
            # and reads /nix/.ro-store/.seed/env/etc/nix.conf.
            mksquashfs $(cat ${closure}/store-paths)${
              lib.optionalString drvsMode " $(cat $recipePathsPath)"
            } $out/store.squashfs \
              -keep-as-directory -all-root -no-hardlinks \
              -comp zstd -Xcompression-level ${toString compressionLevel} \
              -p '.seed d 555 0 0' \
              -p ".seed/registration f 444 0 0 cat ${
                if drvsMode then "$PWD/recipe-registration" else "${closure}/registration"
              }" \
              -p ".seed/env s 777 0 0 ${pathEnv}"${
                lib.optionalString drvsMode '' \
                  -p ".seed/drvs.json f 444 0 0 cat ${drvManifest}"''
              }
          '';

      sourcesSeed = mkVariant [ "sources" ];
      drvsSeed = mkVariant [ "drvs" ];
    in
    # nix-seed is Linux only. the consumer mounts the squashfs as
    # /nix/store and overlays a writable upper for build output; macOS has
    # neither loop-mounts nor overlayfs. fail here rather than producing a
    # seed nothing can run. see DESIGN.md#constraints.
    lib.throwIf (!stdenv.hostPlatform.isLinux) ''
      mkSeed: unsupported system "${system}". nix-seed is Linux only;
      see DESIGN.md#constraints and DESIGN.md#macos.
    '' sourcesSeed;
in
mkSeed
