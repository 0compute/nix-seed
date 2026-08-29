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
      name ? "${
        let
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        package.pname or package.name or "unnamed"
      }.seed",
      tag ? self.rev or self.dirtyRev or null,
      nix ? pkgs.nixVersions.latest,
      nixConf ? "",
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
            [[ -n $@ ]] || set -- /bin/sh
            exec "$@"
          '')
        ];
        Env = lib.mapAttrsToList (name: value: "${name}=${value}") {
          # nix derives its cache dir from HOME; unset yields a relative
          # ".cache/nix" path and fails inside the container.
          HOME = "/tmp";
          LD_LIBRARY_PATH =
            "/lib:/lib64:/lib/" + stdenv.hostPlatform.linuxArch + "-linux-gnu";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };
      } args.config or { };

      corePkgs = [
        # nix from args
        nix
      ]
      ++ (with pkgs; [
        cacert # nix fetchers
        busybox # debug helper
        (writeTextDir "etc/nix/nix.conf" ''
          experimental-features = nix-command flakes
          # XXX: why?
          build-users-group =
          sandbox = false
          # post-build-hook = ${./post-build-hook}
          # no sub, no fallback, build can only happen here
          substitute = false
          fallback = false
          show-trace = true
          eval-cache = false
          ${nixConf}
        '')
      ]);

      # keep a harvested candidate. isDerivation reads only `.type`
      # (cheap); the isNixSeed guard drops a nested seed before its
      # inputDerivation is taken (which would recurse image -> contents
      # -> seedClosure -> inputDerivation); selfFilter is the value-level
      # predicate. tryEval is defence-in-depth for outputs that *throw*
      # (assert/throw are catchable); outputs that fail with a builtin
      # type error tryEval cannot catch must be dropped earlier by
      # selfFilterName, before they are forced at all.
      keepDrv =
        drv:
        let
          r = builtins.tryEval (
            lib.isDerivation drv && !(drv.isNixSeed or false) && selfFilter drv
          );
        in
        if r.success then
          r.value
        else
          lib.warn "mkSeed: skipping a flake output that threw during evaluation" false;

      # derivations the consumer flake exposes.
      selfDrvs =
        let
          byName = attrs: lib.filterAttrs (name: _: selfFilterName name) attrs;
          harvest = attr: lib.attrValues (byName (self.${attr}.${system} or { }));
        in
        lib.filter keepDrv (
          # apps have { type = "app"; program = "..."; }.
          map (app: app.package or null) (
            lib.attrValues (byName (self.apps.${system} or { }))
          )
          ++ harvest "checks"
          ++ harvest "devShells"
          ++ harvest "packages"
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
              lib.concatMap (i: [ i ] ++ collect i) (lib.attrValues (flake.inputs or { }));
          in
          lib.unique (
            map (i: i.outPath) (collect self)
            ++ lib.filter (p: p != null) (
              map (
                drv:
                let
                  r = builtins.tryEval (drv.inputDerivation or drv).outPath;
                in
                if r.success then
                  r.value
                else
                  lib.warn "mkSeed: no build closure for a flake output (threw)" null
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

      image = nix2container.packages.${system}.nix2container.buildImage (
        (lib.removeAttrs args (
          (builtins.attrNames (builtins.functionArgs mkSeed))
          ++ [
            "config"
            "contents"
          ]
        ))
        // {
          inherit config name tag;
          copyToRoot = [
            (pkgs.buildEnv {
              name = "root";
              paths = contents;
              pathsToLink = [
                "/bin"
                "/etc"
                "/lib"
              ]
              ++ lib.optionals githubRunner [ "/__e" ];
              ignoreCollisions = true;
            })
          ];
          maxLayers = 125;
          initializeNixDatabase = true;
        }
      );
    in
    # expose metadata for unit testing and inspection. buildLayeredImage does not
    # support passthru or automatically export its internal arguments
    image
    // {
      inherit
        name
        tag
        contents
        config
        corePkgs
        ;
      # marker so a seed harvesting self.packages skips a nested seed
      # (its inputDerivation would recurse through seedClosure).
      isNixSeed = true;
    };
in
mkSeed
