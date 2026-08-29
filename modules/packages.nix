{ self, ... }:
{

  perSystem =
    { lib, pkgs, ... }:
    {

      packages =
        let
          name = "nix-seed";
          seed = self.lib.mkSeed {
            inherit name pkgs self;
            # emanote's `docs`/`github-io` outputs (apps, checks and
            # packages) fail to evaluate: their pinned haskell-flake runs
            # toJSON over settings holding a functor. Skip by name so they
            # are never forced (a builtin type error tryEval can't catch).
            selfFilterName = name: !(builtins.elem name [ "docs" "github-io" ]);
            selfFilter =
              drv:
              let
                # CHECK: needs the or?
                drvName = drv.name or "";
              in
              !(builtins.any (name: lib.hasPrefix name drvName) [
                # filter self from seed otherwise this is circular
                name
                # filter examples since we want them built in check
                "examples"
              ]);
            # no rev when using `nix build path:.`
            tag = self.rev or self.dirtyRev or null;
          };
        in
        {
          default = seed;
          inherit seed;
        };

    };

}
