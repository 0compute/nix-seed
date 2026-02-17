{

  description = "Zero-setup Nix builds for GitHub actions";

  nixConfig = {
    extra-substituters = [ "https://nix-zero-setup.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-zero-setup.cachix.org-1:lNgsI3Nea9ut1dJDTlks9AHBRmBI+fj9gIkTYHGtAtE="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs =
    inputs:
    let
      lib = import ./lib.nix;
    in
    {
      inherit lib;
    }
    // inputs.flake-utils.lib.eachSystem (import inputs.systems) (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        build-container = lib.mkBuildContainer {
          inherit pkgs;
          name = "nix-zero-setup";
          tag = inputs.self.rev or inputs.self.dirtyRev or null;
        };
      in
      {
        packages = {
          inherit build-container;
          default = build-container;
        };

        checks = {
          unit = import ./tests/unit.nix { inherit pkgs; };
          functional = import ./tests/functional.nix {
            inherit pkgs;
            inherit build-container;
          };
        };

        apps = {

          default = {
            type = "app";
            program = pkgs.lib.getExe (
              let
                inherit (build-container) imageName imageTag;
              in
              pkgs.writeShellApplication {
                name = "self-build";
                text = ''
                  nix() {
                    if command -v nom >/dev/null;
                    then
                      nom "$@"
                    else
                      command nix "$@"
                    fi
                  }
                  nix build .#nixZeroSetupContainer
                  docker load < result
                  docker tag "${imageName}:${imageTag}" "${imageName}:latest"
                '';
              }
            );
          };

        };

      }
    );

}
