{ inputs, ... }: {

  imports = [ inputs.devshell.flakeModule ];

  perSystem = { pkgs, ... }: {

    devshells.default = {
      packages = with pkgs; [
        cosign
        oras
        squashfsTools
      ];
    };

  };

}
