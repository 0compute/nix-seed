{ inputs, ... }: {

  imports = [ inputs.devshell.flakeModule ];

  perSystem = { pkgs, inputs', ... }: {

    devshells.default = {
      packages =
        with pkgs;
        [
          cosign
          dive
          podman
        ]
        ++ (with inputs'.nix2container.packages; [
          default
          skopeo-nix2container
        ]);
    };

  };

}
