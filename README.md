# Nix Zero Setup

A pattern and toolkit for ultra-fast, reproducible GitHub Actions workflows using
Nix-built containers.

## The Problem

Standard Nix CI workflows often look like this:

1. Spin up a generic runner (`ubuntu-latest`).
1. Install Nix (e.g., via `install-nix-action`).
1. Configure caches (Magic Nix Cache, Cachix).
1. Fetch flake inputs.
1. **Finally** build your project.

Steps 2-4 take time, bandwidth, and API calls on *every single job*. While Nix caching
helps, you still pay the "setup tax" repeatedly.

## The Solution: Pre-baked Containers

Instead of configuring the environment at runtime, **bake your build inputs into a
Docker container** using Nix, push it to GHCR, and run your CI jobs *inside* that
container.

### Advantages

1. **Instant Startup**: The environment is ready immediately. No `install-nix-action`,
   no apt installs, no waiting.
1. **Strict Reproducibility**: The CI container is built from the same lockfile as your
   project. If it works in the container locally, it works in CI.
1. **Efficient Caching**: We use `pkgs.dockerTools.buildLayeredImageWithNixDb`. This
   creates Docker layers corresponding to Nix store paths. If you only change your
   source code, the heavy dependency layers (compilers, libraries) remain cached and are
   pulled instantly.
1. **Hermeticity**: Your build environment is isolated from the host runner. No
   interference from pre-installed GitHub Action tools.
1. **Azure Backbone Performance**: Since GHCR and GitHub Actions both run on Azure,
   image pulls happen over the internal high-speed backbone. This means massive
   bandwidth, zero egress costs, negligible latency, and higher reliability compared to
   external registries.

## How It Works

1. **Define a Container**: Use the provided `mkBuildContainer` helper in your
   `flake.nix` to create a Docker image containing Nix, Git, and your project's build
   inputs.
1. **Build & Push**: A dedicated `self-build` app builds this container and pushes it to
   the GitHub Container Registry (GHCR).
1. **Run CI**: Your main CI workflow specifies `container: ghcr.io/owner/repo:tag`.

## Usage

### 1. Import the Library

Add this flake as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-zero-setup = {
      url = "github:your-org/nix-zero-setup";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  # ...
}
```

### 2. Define Your Build Container

In your `flake.nix` outputs:

```nix
  outputs =
    inputs:
    inputs.flake-utils.lib.eachSystem (import inputs.systems) (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        lib = inputs.nix-zero-setup.lib pkgs;
      in
      {
        packages.build-container = lib.mkBuildContainer {
          name = "my-project-build";
          # Automatically include buildInputs from your main package
          drv = inputs.self.packages.${system}.default;
          # Or add extra packages manually
          contents = with pkgs; [
            jq
            ripgrep
          ];
        };
      }
    );
```

### 3. Setup the Push Workflow

Create a `.github/workflows/container.yml` to update the container when dependencies
change:

```yaml
name: Build Container
on:
  push:
    branches: [ main ]
    paths: [ 'flake.lock', 'flake.nix' ]

jobs:
  push:
    runs-on: ubuntu-latest
    permissions:
      packages: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v25
      - run: nix run .#apps.x86_64-linux.github-action
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 4. Use in Your Main Workflow

In your main `.github/workflows/ci.yml`:

```yaml
name: CI
on: [ push, pull_request ]

jobs:
  test:
    runs-on: ubuntu-latest
    # Run directly inside the pre-baked environment
    container: ghcr.io/your-org/my-project-build:latest
    steps:
      - uses: actions/checkout@v4
      - run: nix build
      - run: nix flake check
```

## Examples

We provide several reference implementations demonstrating how to bake different types
of heavy build environments:

- **[Python (ML Stack)](examples/python):** Demonstrates baking a heavy Machine Learning
  environment (PyTorch, NumPy, Pandas) using `pyproject-nix`. This avoids re-downloading
  and re-linking massive Python wheels on every CI run.
- **[C++ (Boost)](examples/cpp-boost):** Shows how to include system-level libraries
  like Boost and build tools (CMake, Ninja, GCC) in the container, skipping the overhead
  of compiling or installing these dependencies at runtime.
- **[Rust (Toolchain)](examples/rust-app):** Illustrates baking the full Rust toolchain
  (`cargo`, `rustc`, `clippy`, `rust-analyzer`) into the image, eliminating the need to
  download and setup Rust for each job.
