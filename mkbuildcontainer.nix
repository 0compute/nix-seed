{
  pkgs,
  inputsFrom ? [ ],
  name ? (
    if inputsFrom != [ ] then
      "${
        (pkgs.lib.head inputsFrom).pname or (pkgs.lib.head inputsFrom).name
          or "unnamed"
      }-nix-build-container"
    else
      "nix-zero-setup-env"
  ),
  nix ? pkgs.nixVersions.latest,
  nixConf ? ''
    experimental-features = nix-command flakes
  '',
  ...
}@args:
let
  extractedInputs = pkgs.lib.concatMap (
    d:
    pkgs.lib.concatMap (attr: d.${attr} or [ ]) [
      "buildInputs"
      "nativeBuildInputs"
      "propagatedBuildInputs"
      "propagatedNativeBuildInputs"
    ]
  ) inputsFrom;

  contents = [
    nix
  ]
  ++ (with pkgs; [
    bashInteractive # for debug, only adds 4mb
    cacert # for fetchers
    coreutils # basic unix tools
    git # required for flakes
  ])
  ++ extractedInputs
  ++ args.contents or [ ];

  config = {
    Entrypoint = [ (pkgs.lib.getExe nix) ];
    Env = pkgs.lib.mapAttrsToList (name: value: "${name}=${value}") {
      USER = "root";
      # requires "sandbox = false" because unprivileged containers lack the
      # kernel privileges (unshare for namespaces) required to create it
      # we also disable build-users-group because containers often lack them
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
    (pkgs.lib.removeAttrs args [
      "contents"
      "config"
      "inputsFrom"
      "nix"
      "nixConf"
      "pkgs"
    ])
    // {
      inherit name contents config;
      # nix needs /tmp to build. we also create a standard /bin env
      extraCommands = ''
        mkdir -m 1777 tmp
        mkdir -p bin
        for c in ${pkgs.lib.concatStringsSep " " contents}; do
          if [ -d "$c/bin" ]; then
            ln -s "$c"/bin/* bin/ || true
          fi
        done
      '';
    }
  );
in
# expose metadata for unit testing and inspection. buildLayeredImageWithNixDb
# does not support passthru or automatically export its internal arguments
image // { inherit contents config; }
