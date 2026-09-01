{

  perSystem =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {

      apps =
        let

          mkApp = attrs: {
            type = "app";
            program = lib.getExe (pkgs.writeShellApplication attrs);
          };

        in
        {

          syncWorkflows = mkApp {
            name = "sync-workflows";
            runtimeInputs = with pkgs; [
              gitMinimal
              nixVersions.latest
              rsync
            ];
            text = ''
              rsync --archive --delete ${config.githubActions.workflowsDir}/ \
                $(git rev-parse --show-toplevel)/.github/
            '';
          };

        };

    };

}
