machine.wait_for_unit("docker.service")
machine.succeed("docker load < @img@")

# verify Nix is available and functional in the container
machine.succeed("docker run --rm --entrypoint nix @tag@ --version")

# create a minimal Nix project to build inside the container
machine.succeed("mkdir -p /tmp/test-project")
machine.copy_from_host("@mkbuildcontainer@", "/tmp/test-project/mkbuildcontainer.nix")
machine.copy_from_host("@testflake@", "/tmp/test-project/flake.nix")

# initialize git so Nix sees the files in the flake
machine.succeed("cd /tmp/test-project && git init && git add .")

# run nix eval inside the container to verify flake evaluation works
machine.succeed(
    " ".join(
        (
            "docker run",
            "--rm",
            "-v /tmp/test-project:/src",
            "-w /src",
            "@tag@",
            "eval",
            "--impure",
            "--accept-flake-config",
            "--extra-experimental-features 'nix-command flakes'",
            ".#default.name",
        )
    )
)
