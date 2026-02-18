{ pkgs, mkBuildContainer }:
pkgs.testers.runNixOSTest {

  name = "func";

  nodes.machine =
    { pkgs, ... }:
    {
      virtualisation = {
        docker.enable = true;
        memorySize = 2048;
        diskSize = 4096;
      };
      environment.systemPackages = [ pkgs.git ];
    };

  testScript =
    let
      img = mkBuildContainer {
        inherit pkgs;
        name = "nix-zero-setup";
      };
      tag = with img; "${imageName}:${imageTag}";
    in
    builtins.readFile (
      pkgs.replaceVars ./functional.py {
        inherit img tag;
        mkbuildcontainer = ./../mkbuildcontainer.nix;
        pkgs-path = pkgs.path;
      }
    );

}
