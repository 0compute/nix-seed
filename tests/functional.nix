{ pkgs, build-container }:
pkgs.testers.runNixOSTest {
  name = "nix-zero-setup-functional";
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
      # use the image name and tag from the derivation
      img = build-container;
      tag = "${img.imageName}:${img.imageTag}";
    in
    ''
      machine.wait_for_unit("docker.service")
      machine.succeed("docker load < ${img}")

      # verify Nix is available and functional in the container
      machine.succeed("docker run --rm --entrypoint nix ${tag} --version")

      # create a minimal Nix project to build inside the container
      # we use builtins.derivation to avoid stdenv/nixpkgs dependencies
      machine.succeed("mkdir -p /tmp/test-project")
      machine.copy_from_host("${../lib.nix}", "/tmp/test-project/lib.nix")

      flake_content = """
      {
        outputs = _: {
          packages.x86_64-linux.default = 
            let 
              # minimal mock pkgs for lib.nix
              pkgs = { 
                lib = (import "${pkgs.path}" { }).lib;
                nix = { outPath = "/bin/nix"; };
                coreutils = { outPath = "/bin"; };
                bashInteractive = { outPath = "/bin/bash"; };
                dockerTools.buildLayeredImageWithNixDb = args: 
                  derivation {
                    name = args.name;
                    builder = "/bin/sh";
                    args = [ "-c" "/bin/touch \$out" ];
                    system = "x86_64-linux";
                    PATH = "/bin";
                  };
                cacert = { outPath = "/etc/ssl/certs/ca-bundle.crt"; };
              };
              lib = import ./lib.nix;
            in lib.mkBuildContainer { 
              inherit pkgs;
              name = "test-container";
              inputsFrom = [ pkgs.coreutils ];
            };
        };
      }
      """
      machine.succeed(f"echo '{flake_content}' > /tmp/test-project/flake.nix")
      # initialize git so Nix sees the files in the flake
      machine.succeed("cd /tmp/test-project && git init && git add .")

      # run the build inside the container
      # we provide a mock NIX_PATH for lib.nix to import <nixpkgs/lib> or similar
      machine.succeed(
        "docker run --rm " +
        "-v /tmp/test-project:/src -w /src " +
        "-e NIX_PATH=nixpkgs=${pkgs.path} " +
        "-v ${pkgs.path}:${pkgs.path}:ro " +
        "${tag} build --offline --impure --verbose --accept-flake-config --extra-experimental-features 'nix-command flakes' .#default"
      )
    '';
}
