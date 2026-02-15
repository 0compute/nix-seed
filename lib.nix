{
  mkBuildContainer =
    {
      pkgs,
      drv ? null,
      name ? "${drv.pname or drv.name or "unnamed"}-build-container",
      nix ? pkgs.nixVersions.latest,
      nixConf ? ''
        experimental-features = nix-command flakes
      '',
      ...
    }@args:
    let
      contents = [
        nix
      ]
      ++ (with pkgs; [
        bashInteractive # for debug, only adds 4MB
        cacert # for fetchers
      ])
      ++ pkgs.lib.flatten (
        map (attr: drv.${attr} or [ ]) [
          "buildInputs"
          "nativeBuildInputs"
          "propagatedBuildInputs"
          "propagatedNativeBuildInputs"
        ]
      )
      ++ args.contents or [ ];

      config = {
        Entrypoint = [ (pkgs.lib.getExe nix) ];
        Env = pkgs.lib.mapAttrsToList (name: value: "${name}=${value}") {
          USER = "root";
          # requires "sandbox = false" because unprivileged containers lack the
          # kernel privileges (unshare for namespaces) required to create it.
          # we also disable build-users-group because containers often lack them.
          NIX_CONFIG = ''
            sandbox = false
            build-users-group =
            ${nixConf}
          '';
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          PATH = "/bin:/usr/bin:/sbin:/usr/sbin";
        };
      };

      image = pkgs.dockerTools.buildLayeredImageWithNixDb (
        {
          inherit name contents config;

          # nix needs /tmp to build
          extraCommands = "mkdir -m 1777 tmp";
        }
        // pkgs.lib.removeAttrs args [
          "contents"
          "drv"
          "nix"
          "nixConf"
          "pkgs"
        ]
      );
    in
    image // { inherit contents config; };
}
