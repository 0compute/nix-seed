{ inputs, ... }:
{

  imports = [ inputs.github-actions-nix.flakeModule ];

  flake.githubActions = {

    enable = true;

    workflows.seed = {

      name = "Seed";

      on = {
        push = { };
        pullRequest = { };
      };

      jobs = {

        build = {
          runsOn = "ubuntu-latest";
          permissions = {
            # allow checkout and other read-only ops; this is the default
            # but specifying a permissions block drops defaults back to
            # `none`
            contents = "read";
            # minting an OIDC token lets COSIGN_EXPERIMENTAL=1 keep cosign
            # signing non-interactive instead of invoking the device flow.
            id-token = "write";
            # allow push to registry
            packages = "write";
          };
          steps = [
            {
              name = "Checkout";
              uses = "actions/checkout@v6";
            }
            {
              name = "Build Seed";
              uses = "./seed";
              "with".github_token = "$${{ secrets.GITHUB_TOKEN }}";
            }
          ];
        };

      };

    };

  };

}
