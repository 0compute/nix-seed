{ inputs, ... }:
{

  imports = [
    inputs.emanote.flakeModule
    inputs.mkdocs-flake.flakeModules.default
  ];

  perSystem = {

    documentation.mkdocs-root = ../doc;

    emanote.sites = rec {

      # https://github.com/srid/emanote/blob/master/nix/modules/flake-parts/flake-module/site/default.nix
      docs = {
        layers = [
          {
            path = ./.;
            pathString = ".";
          }
        ];
        # port = 8080;
      };

      # Optimized for deploying to https://<user>.github.io/<repo-name> URLs
      github-io = docs // {
        check = false;
        extraConfig.template.baseUrl = "/emanote-template/";
      };

    };

  };
}
