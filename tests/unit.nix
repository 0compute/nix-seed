{ pkgs, mkBuildContainer }:
let

  results = pkgs.lib.runTests {
    testEnvConfig = {
      expr =
        pkgs.lib.sort (left: right: left < right)
          (mkBuildContainer {
            inherit pkgs;
            inputsFrom = [ pkgs.hello ];
            nixConf = "extra-features = nix-command";
          }).config.Env;
      expected = pkgs.lib.sort (left: right: left < right) [
        "USER=root"
        "GIT_TEXTDOMAINDIR=${pkgs.git}/share/locale"
        "GIT_INTERNAL_GETTEXT_TEST_FALLBACKS="
        "HOME=/tmp"
        (
          "NIX_CONFIG="
          + "sandbox = false\n"
          + "build-users-group =\n"
          + "extra-features = nix-command\n"
        )
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        (
          "LD_LIBRARY_PATH=/lib:/lib64:/lib/"
          + pkgs.stdenv.hostPlatform.linuxArch
          + "-linux-gnu"
        )
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

    testInputsFromMerging =
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
      {
        expr = container.contents;
        expected =
          container.corePkgs
          ++ (with pkgs; [
            hello
            ripgrep
            jq
          ]);
      };

    testContentsMerging =
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
      {
        expr = container.contents;
        expected =
          container.corePkgs
          ++ (with pkgs; [
            hello
            jq
          ]);
      };
  };
in
if results == [ ] then
  pkgs.runCommand "unit-tests" { } "touch $out"
else
  throw (builtins.toJSON results)
