{ pkgs, mkBuildContainer }:
let

  results = pkgs.lib.runTests {
    testEnvConfig = {
      expr =
        pkgs.lib.sort (a: b: a < b)
          (mkBuildContainer {
            inherit pkgs;
            inputsFrom = [ pkgs.hello ];
            nixConf = "extra-features = nix-command";
          }).config.Env;
      expected = pkgs.lib.sort (a: b: a < b) [
        "USER=root"
        "NIX_CONFIG=sandbox = false\nbuild-users-group =\nextra-features = nix-command\n"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "PATH=/bin:/usr/bin:/sbin:/usr/sbin"
      ];
    };

    testDefaultName = {
      expr =
        (mkBuildContainer {
          inherit pkgs;
          inputsFrom = [ pkgs.hello ];
        }).name;
      expected = "hello-nix-build-container.tar.gz";
    };

    testCustomName = {
      expr =
        (mkBuildContainer {
          inherit pkgs;
          name = "custom";
        }).name;
      expected = "custom.tar.gz";
    };

    testInputsFromMerging = {
      expr =
        let
          drv1 = pkgs.stdenv.mkDerivation {
            pname = "test1";
            version = "1.0";
            buildInputs = with pkgs; [ hello ];
          };
          drv2 = pkgs.stdenv.mkDerivation {
            pname = "test2";
            version = "1.0";
            nativeBuildInputs = with pkgs; [ ripgrep ];
          };
          container = mkBuildContainer {
            inherit pkgs;
            inputsFrom = [
              drv1
              drv2
            ];
            contents = with pkgs; [ jq ];
          };
        in
        container.contents;
      expected = with pkgs; [
        nixVersions.latest
        bashInteractive
        cacert
        coreutils
        git
        hello
        ripgrep
        jq
      ];
    };

    testContentsMerging = {
      expr =
        let
          drv = pkgs.stdenv.mkDerivation {
            pname = "test";
            version = "1.0";
            buildInputs = with pkgs; [ hello ];
          };
          container = mkBuildContainer {
            inherit pkgs;
            inputsFrom = [ drv ];
            contents = with pkgs; [ jq ];
          };
        in
        container.contents;
      expected = with pkgs; [
        nixVersions.latest
        bashInteractive
        cacert
        coreutils
        git
        hello
        jq
      ];
    };
  };
in
if results == [ ] then
  pkgs.runCommand "unit-tests" { } "touch $out"
else
  throw (builtins.toJSON results)
