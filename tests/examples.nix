# e2e test: build all example projects
{ pkgs, mkBuildContainer, flake-utils, pyproject-nix, system }:
let
  inherit (pkgs) lib;

  # inputs for example flakes
  availableInputs = {
    self = { };
    nixpkgs.legacyPackages.${system} = pkgs;
    nix-zero-setup.lib = { inherit mkBuildContainer; };
    inherit flake-utils pyproject-nix;
  };

  examplesDir = ../examples;

  exampleNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir examplesDir)
  );

  buildExample = name:
    let
      flake = import (examplesDir + "/${name}/flake.nix");
      outputs = flake.outputs availableInputs;
    in
    outputs.packages.${system}.nix-build-container;

  containers = map (name: {
    inherit name;
    container = buildExample name;
  }) exampleNames;

in
pkgs.runCommand "examples"
  {
    passAsFile = [ "containerList" ];
    containerList = lib.concatMapStringsSep "\n" (c: "${c.name}=${c.container}") containers;
  }
  ''
    echo "Building example containers..."
    while IFS='=' read -r name path; do
      test -f "$path" || { echo "FAIL: $name ($path)"; exit 1; }
      echo "OK: $name"
    done < "$containerListPath"
    mkdir -p $out
  ''
