{ inputs, ... }: {

  imports = [ inputs.devshell.flakeModule ];

  perSystem = { lib, pkgs, ... }: {

    devshells.default = {
      packages = with pkgs; [
        cosign
        oras
      ]
      # squashfs is the linux delivery format; darwin ships a disk image
      # built with hdiutil, a system binary rather than a nixpkgs one.
      # see DESIGN.md#delivery.
      ++ lib.optionals stdenv.hostPlatform.isLinux [ squashfsTools ];
    };

  };

}
