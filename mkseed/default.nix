{ nix2container }:
let
  mkSeed =
    {
      pkgs,
      self,
      selfFilter ? (_drv: true),
      # name from flake default package
      name ? "${
        self.packages.${pkgs.stdenv.hostPlatform.system}.default.pname or "noname"
      }.seed",
      nix ? pkgs.nixVersions.latest,
      nixConf ? "",
      # TODO: hook in seedCfg
      githubRunner ? true,
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
          post-build-hook = ${./post-build-hook}
          # no sub, no fallback, build can only happen here
          substitute = false
          fallback = false
          show-trace = true
          eval-cache = false
          ${nixConf}
        '')
        # (writeShellScriptBin "nix" ''
        #   mkdir /root
        #   export HOME=/root
        #   ${lib.getExe nix} "$@"
        # '')
      ]);

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
        ++ (lib.concatMap
          (
            drv:
            lib.concatMap (attr: drv.${attr} or [ ]) [
              "buildInputs"
              "nativeBuildInputs"
              "propagatedBuildInputs"
              "propagatedNativeBuildInputs"
            ]
          )
          (
            let
              getDerivations =
                attr: lib.filter selfFilter (lib.attrValues (self.${attr}.${system} or { }));
            in
            # apps have { type = "app"; program = "..."; }.
            lib.filter (drv: lib.isDerivation drv && selfFilter drv) (
              map (app: app.package or null) (lib.attrValues (self.apps.${system} or { }))
            )
            ++ getDerivations "checks"
            ++ getDerivations "devShells"
            ++ getDerivations "packages"
          )
        )
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
          inherit config name;
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
            })
          ];
          maxLayers = 100;
          initializeNixDatabase = true;
        }
      );
    in
    # expose metadata for unit testing and inspection. buildLayeredImage does not
    # support passthru or automatically export its internal arguments
    image // { inherit contents config corePkgs; };
in
mkSeed
