# ruff: noqa
# from typing import TYPE_CHECKING
#
# if TYPE_CHECKING:
#     from nixos_test_driver.driver import Machine
#
#     machine: Machine = None

machine.wait_for_unit("docker.service")
machine.succeed("docker load < @img@")

# verify Nix is available and functional in the container
machine.succeed("docker run --rm --entrypoint nix @tag@ --version")

# create a minimal Nix project to build inside the container
# we use builtins.derivation to avoid stdenv/nixpkgs dependencies
machine.succeed("mkdir -p /tmp/test-project")
machine.copy_from_host("@mkbuildcontainer@", "/tmp/test-project")

flake_content = """
{
outputs = _: {
    packages.x86_64-linux.default =
    let
        # minimal mock pkgs for lib.nix
        pkgs = {
        lib = (import "@pkgs-path@" { }).lib;
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
        mkBuildContainer = import ./mkbuildcontainer.nix;
    in mkBuildContainer {
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
    " ".join(
        (
            "docker run",
            "--rm",
            "-v /tmp/test-project:/src",
            "-w /src",
            "@tag@",
            "build",
            "--offline",
            "--impure",
            "--verbose",
            "--accept-flake-config",
            "--extra-experimental-features 'nix-command flakes'",
            ".#default",
        )
    )
)
