{
  pkgs,
  self ? null,
  selfFilter ? (_drv: true),
  inputsFrom ? [ ],
  # name from flake default package or first inputsFrom
  name ? (
    let
      base = "nix-build-container";
    in
    if self != null then
      self.packages.${pkgs.stdenv.hostPlatform.system}.default.pname
    else if inputsFrom != [ ] then
      "${
        (pkgs.lib.head inputsFrom).pname or (pkgs.lib.head inputsFrom).name
          or "unnamed"
      }-${base}"
    else
      base
  ),
  nix ? pkgs.nixVersions.latest,
  nixConf ? ''
    experimental-features = nix-command flakes
  '',
  # these are tiny and make debug much easier - override to empty if desired
  debugTools ? with pkgs; [
    bashInteractive
    coreutils
  ],
  ...
}@args:
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;

  corePkgs =
    with pkgs;
    [
      # nix from args
      nix
      # nix fetchers
      cacert
      # actions runtime
      glibc
      stdenv.cc.cc.lib
      # actions/checkout
      git
      gnutar
      gzip
      nodejs
    ]
    ++ lib.optionals (debugTools != [ ]) debugTools;

  contents =
    corePkgs
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
        # pkgs.mkShell interface
        inputsFrom
        # extract from flake outputs
        ++ (
          if self == null then
            [ ]
          else
            let
              getDerivations =
                attr:
                lib.filter selfFilter (
                  lib.attrValues (self.${attr}.${system} or { })
                );
            in
            getDerivations "packages"
            ++ getDerivations "checks"
            # Apps have { type = "app"; program = "..."; }.
            # Extract if there's a package attr.
            ++ lib.filter (drv: lib.isDerivation drv && selfFilter drv) (
              map
                (app: app.package or null)
                (lib.attrValues (self.apps.${system} or { }))
            )
        )
      )
    )
    ++ args.contents or [ ];

  config = lib.recursiveUpdate {
    Entrypoint = [ (lib.getExe nix) ];
    Env = lib.mapAttrsToList (name: value: "${name}=${value}") {
      HOME = "/tmp";
      USER = "root";
      GIT_TEXTDOMAINDIR = "${pkgs.git}/share/locale";
      GIT_INTERNAL_GETTEXT_TEST_FALLBACKS = "";
      # requires "sandbox = false" because unprivileged containers lack the
      # kernel privileges (unshare for namespaces) required to create it
      # we also disable build-users-group because containers often lack them
      NIX_CONFIG = ''
        sandbox = false
        build-users-group =
        ${nixConf}
      '';
      LD_LIBRARY_PATH =
        "/lib:/lib64:/lib/"
        + pkgs.stdenv.hostPlatform.linuxArch
        + "-linux-gnu";
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      PATH = "/bin:/usr/bin:/sbin:/usr/sbin";
    };
  } (args.config or { });

  image = pkgs.dockerTools.buildLayeredImageWithNixDb (
    (lib.removeAttrs args [
      "config"
      "contents"
      "flake"
      "flakeFilter"
      "inputsFrom"
      "nix"
      "nixConf"
      "pkgs"
      "self"
      "selfFilter"
    ])
    // {
      inherit name contents config;
      extraCommands = ''
        # nix needs /tmp to build
        mkdir --mode=1777 tmp
        # actions expect node here
        externals=__e
        mkdir $externals
        nodeDir=$externals/node${lib.versions.major pkgs.nodejs.version}
        mkdir --parents $nodeDir/bin
        ln --symbolic ${lib.getExe pkgs.nodejs} $nodeDir/bin/node
        libc=${pkgs.glibc}/lib/libc.so.6
        libstdcpp=${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6
        # Actions runtime expects glibc libs at the multiarch path.
        multiarchDir=lib/${pkgs.stdenv.hostPlatform.linuxArch}-linux-gnu
        mkdir --parents $multiarchDir
        ln --symbolic $libc $multiarchDir/libc.so.6
        ln --symbolic $libstdcpp $multiarchDir/libstdc++.so.6
        # Provide default loader paths for runtime linking.
        versionedLibstdcpp=$(readlink --canonicalize $libstdcpp)
        versionedLibstdcppName=$(basename $versionedLibstdcpp)
        mkdir --parents lib lib64
        ln --force --symbolic $libc lib/libc.so.6
        ln --force --symbolic $libstdcpp lib/libstdc++.so.6
        ln --force --symbolic $libstdcpp lib64/libstdc++.so.6
        ln --force --symbolic $versionedLibstdcpp lib/$versionedLibstdcppName
        ln --force --symbolic $versionedLibstdcpp lib64/$versionedLibstdcppName
      '';
    }
  );
in
# expose metadata for unit testing and inspection. buildLayeredImageWithNixDb
# does not support passthru or automatically export its internal arguments
image // { inherit contents config corePkgs; }
