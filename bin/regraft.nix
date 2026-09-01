# rebuild a derivation from a patched `nix derivation show` node (JSON
# file named by NIX_SEED_REGRAFT), re-attaching the input string contexts
# so builtins.derivation recomputes the canonical drvPath/outPath from
# the baked input drvs. evaluated with the classic (impure) evaluator;
# no flakes, no nixpkgs. see doc/drv-seeds.md.
let
  j = builtins.fromJSON (builtins.readFile (builtins.getEnv "NIX_SEED_REGRAFT"));

  outputNames = builtins.attrNames j.outputs;

  # fixed-output / structured-attrs recipes are out of scope
  guard =
    if j.env ? __json || j.env.__structuredAttrs or "" == "1" then
      throw "regraft: structuredAttrs derivations are not supported"
    else if builtins.any (o: j.outputs.${o} ? hash) outputNames then
      throw "regraft: fixed-output derivations are not supported"
    else
      true;

  # the original env.outputs string fixes the output order; attrNames is
  # only the fallback (order feeds the ATerm text, so it must match).
  outputsList =
    if j.env ? outputs then
      builtins.filter (s: builtins.isString s && s != "") (
        builtins.split " " j.env.outputs
      )
    else
      outputNames;

  # every input as string context: inputDrvs with their wanted outputs,
  # inputSrcs (including the grafted src) as plain paths. the v4 schema
  # lists inputs as store basenames; contexts need full paths. carried on
  # the name attr -- context placement does not affect the drv text, only
  # the computed inputDrvs/inputSrcs sets.
  full = b: "${builtins.storeDir}/${b}";
  ctx =
    builtins.listToAttrs (
      map (n: {
        name = full n;
        value = { outputs = j.inputs.drvs.${n}.outputs; };
      }) (builtins.attrNames j.inputs.drvs)
    )
    // builtins.listToAttrs (
      map (s: {
        name = full s;
        value = { path = true; };
      }) j.inputs.srcs
    );

  attrs =
    removeAttrs j.env outputNames
    // {
      inherit (j) name system args;
      # the context rides on builder (name must stay context-free);
      # placement does not affect the drv text, only the input sets.
      builder = builtins.appendContext j.builder ctx;
      outputs = outputsList;
    }
    // (
      # mkDerivation's boolean, serialized into the env as ""/"1"; the
      # derivation primitive wants the bool back (it re-serializes
      # identically, so the round-trip preserves the drv text).
      if j.env ? __structuredAttrs then
        { __structuredAttrs = j.env.__structuredAttrs == "1"; }
      else
        { }
    );
in
assert guard;
builtins.derivation attrs
