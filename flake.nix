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
    // (inputs.flake-utils.lib.eachSystem (import inputs.systems) (
      system:
      let

        pkgs = inputs.nixpkgs.legacyPackages.${system};

        nixZeroSetupContainer = lib.mkBuildContainer {
          inherit pkgs;
          name = "nix-zero-setup";
          tag = with inputs; self.rev or self.dirtyRev or null;
        };

      in
      {

        packages = {
          inherit nixZeroSetupContainer;
          default = nixZeroSetupContainer;
          example = lib.mkBuildContainer {
            inherit pkgs;
            drv = pkgs.hello;
          };
        };

        checks = {
          unit = import ./tests/unit.nix { inherit pkgs; };
        };

        apps = {

          default = {
            type = "app";
            program = lib.getExe (
              let
                inherit (nixZeroSetupContainer) imageName imageTag;
              in
              pkgs.writeShellApplication {
                name = "self-build";
                text = ''
                  nix() {
                    if command -v nom >/dev/null; then
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

          github-action = {
            type = "app";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "github-action";
                text = ''
                  nix build "$@"
                  docker load < result
                  name="ghcr.io/$GITHUB_REPOSITORY"
                  for tag in "$GITHUB_SHA" "$(git describe --tags --always)" latest; do
                    docker tag "''${GITHUB_REPOSITORY##*/}:$GITHUB_SHA" "$name:$tag"
                  done
                  docker login ghcr.io \
                    --username "$GITHUB_ACTOR" \
                    --password-stdin <<< "$GITHUB_TOKEN"
                  docker push --all-tags "$name"
                '';
              }
            );
          };

        };

      }
    ));

}
