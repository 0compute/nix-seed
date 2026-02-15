{ pkgs }:
let
  inherit (pkgs) lib;
  mockPkgs = pkgs // {
    dockerTools = pkgs.dockerTools // {
      buildLayeredImageWithNixDb = args: args;
    };
  };
  nixZeroSetupLib = import ../lib.nix mockPkgs;

  results = lib.runTests {
    testEnvConfig = {
      expr = lib.sort (a: b: a < b) (
        (nixZeroSetupLib.mkBuildContainer {
          drv = pkgs.hello;
          nixConf = "extra-features = nix-command";
        }).config.Env
      );
      expected = lib.sort (a: b: a < b) [
        "USER=root"
        "NIX_CONFIG=sandbox = false\nextra-features = nix-command\n"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
    };

    testDefaultName = {
      expr = (nixZeroSetupLib.mkBuildContainer { drv = pkgs.hello; }).name;
      expected = "hello-build-container";
    };

    testCustomName = {
      expr = (nixZeroSetupLib.mkBuildContainer { name = "custom"; }).name;
      expected = "custom";
    };

    testContentsMerging = {
      expr =
        let
          drv = pkgs.stdenv.mkDerivation {
            pname = "test";
            version = "1.0";
            buildInputs = [ pkgs.hello ];
          };
          container = nixZeroSetupLib.mkBuildContainer {
            inherit drv;
            contents = [ pkgs.jq ];
          };
        in
        container.contents;
      expected = with pkgs; [
        nixVersions.latest
        bashInteractive
        cacert
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

