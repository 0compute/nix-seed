pkgs:
pkgs.lib.extend (
  final: _prev:
  let
    lib = final;
  in
  {

    mkBuildContainer =
      {
        drv ? null,
        name ? "${drv.pname or drv.name or "unnamed"}-build-container",
        nix ? pkgs.nixVersions.latest,
        nixConf ? ''
          experimental-features = nix-command flakes
        '',
        ...
      }@args:
      pkgs.dockerTools.buildLayeredImageWithNixDb (
        {

          # not actually necessary since args are merged below, leaving so lints can
          # see that the name arg is used
          inherit name;

          # nix needs /tmp to build
          extraCommands = "mkdir -m 1777 tmp";

          contents = [
            nix
          ]
          ++ (with pkgs; [
            bashInteractive # for debug, only adds 4MB
            cacert # for fetchers
          ])
          ++ lib.flatten (
            map (attr: drv.${attr} or [ ]) [
              "buildInputs"
              "nativeBuildInputs"
              "propagatedBuildInputs"
              "propagatedNativeBuildInputs"
            ]
          )
          ++ args.contents or [ ];

          config = {
            Entrypoint = [
              (lib.getExe nix)
              "--no-pager"
            ];
            Env = pkgs.lib.mapAttrsToList (name: value: "${name}=${value}") {
              USER = "root";
              # requires "sandbox = false" because unprivileged containers lack the
              # kernel privileges (unshare for namespaces) required to create it
              NIX_CONFIG = ''
                sandbox = false
                ${nixConf}
              '';
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            };
          };

        }
        # merge in args minus what we've consumed
        // lib.removeAttrs args [
          "contents"
          "drv"
          "nix"
          "nixConf"
        ]
      );

  }
)
