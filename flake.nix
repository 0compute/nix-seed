{

  description = "Zero-setup Nix builds for GitHub actions";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs:
    let
      mkBuildContainer = import ./mkbuildcontainer.nix;
    in
    {
      lib = { inherit mkBuildContainer; };
    }
    // inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let

        pkgs = inputs.nixpkgs.legacyPackages.${system};

        nix-build-container = mkBuildContainer {
          inherit pkgs;
          name = "nix-zero-setup";
          tag = inputs.self.rev or inputs.self.dirtyRev or null;
        };

      in
      {

        checks =
          let
            attrs = { inherit pkgs mkBuildContainer; };
          in
          {
            utest = import ./tests/unit.nix attrs;
            ftest = import ./tests/functional.nix attrs;
          };

        packages = {
          inherit nix-build-container;
          default = nix-build-container;
        };

      }
    );

}
