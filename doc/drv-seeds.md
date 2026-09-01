# drv-baked seeds: zero-eval consume, runtime src graft

Status: implemented through rollout step 2. One `mkSeed` call yields
the sources-mode seed with `.sources`/`.drvs` variant attributes
(cross-linked passthru); consumers pick by attribute, e.g.
`(mkSeed { ... }).drvs`.

## Problem (measured)

A warm consumer job splits into: blob restore (scales with seed size) +
~1s mount/load-db + flake eval (1-5s) + the project's own compile.
Profiling the hello seed: the nixpkgs *source tree* is the single
largest item (189 MB uncompressed), and one exists in every seed. Both
the sources and the per-job eval are artifacts of one design choice:
the consumer re-evaluates the flake every run.

## Insight: sources feed the evaluator, never the build

The consumer pipeline is (1) flake resolution, (2) evaluation ->
`.drv` files, (3) realisation. Sources are only read in 1-2. A `.drv`
is a closed recipe: builder, args, env with every reference resolved
to concrete store paths; `inputSrcs` by absolute path; `inputDrvs` by
drv path. Realisation never invokes the evaluator; builders consume
dep *outputs*, which the seed already bakes via `inputDerivation`.
No derivation references the nixpkgs source tree.

> Sources are the cookbook; the drv closure is the written-out recipe
> cards with exact pantry locations; the baked outputs are the pantry.
> The seeder cooked from the cookbook once, at seed time. Ship cards +
> pantry; the cookbook stays home.

Corollary: the project's own `src` is an inputSrc of its drv, so the
pinned build needs no checkout, no libgit2 safe.directory, no GC_DONT_GC.

## variants (seed attributes)

- `.sources` (the default result): flake input sources baked;
  consumer runs `nix build ./dir` -- proves offline *evaluation*.
- `.drvs`: the target's recipe set baked + a `.seed/drvs.json`
  manifest; consumer runs `nix-store --realise` -- zero eval, no
  flake-input sources in the blob.
- a future combined variant: fast path + an integrity cross-check
  (`nix path-info --derivation ./dir == .seed/drvs.json.default.drv`),
  turning "the seed matches the repo" from assumption into assertion.

## Spike finding: closureInfo cannot collect recipes

The obvious mechanism -- root
`builtins.unsafeDiscardOutputDependency drv.drvPath` in
`closureInfo { rootPaths }` -- fails:
`exportReferencesGraph` over a `.drv` path uses the historical
"build-time dependencies" semantics and demands the **full transitive
output closure be valid** (observed: `path '...-autoreconf-hook' is
not valid` -- an *output* of a bootstrap-depth hook, never realised
locally). Baking that way would force the seeder to realise or
substitute every transitive output down to bootstrap: gigabytes per
seed, defeating the point.

## Corrected collection: eval-time graph walk

Collect the recipe set in Nix at eval time, with no store queries:

1. `builtins.genericClosure` from `target.drvPath`; the operator
   `builtins.readFile`s each `.drv` (they exist -- this very eval
   instantiated them) and extracts `/nix/store/...` substrings.
   `.drv`-suffixed hits are the direct inputDrvs (recurse); the rest,
   minus each drv's own declared outputs, are inputSrcs.
2. Root every collected file individually via
   `builtins.appendContext path` -- plain path inputs of the seed
   derivation, no exportReferencesGraph involvement, nothing built.
3. Registration: the consumer's `--load-db` must know the recipe
   files, and a registered path's references must be present, so
   registration entries need the *correct* reference lists -- which
   step 1 already computed. Emit the graph as JSON into the seed
   build; the builder formats load-db records, computing
   narHash/narSize with `nix-hash`/`nix-store --dump` over each file,
   and concatenates them onto closureInfo's registration.

Realisation then reads the target drv plus its input drvs, finds every
input output already valid, and builds exactly one derivation.

Open verifications for the next spike: eval cost of readFile over a
few thousand drvs; exact load-db record format parity; whether realise
touches more than the drv files collected (it should not: goals stop
at valid outputs).

## Manifest

```json
// .seed/drvs.json
{ "bake": ["drvs"],
  "default": { "drv": "/nix/store/xxx.drv",
               "src": "/nix/store/yyy-source",   // absent if no src
               "srcName": "source" } }
```

`bin/build` already implements the consumer side: manifest present ->
realise (refusing src-bearing targets until the graft lands); absent ->
today's eval path.

## Runtime src graft (the "updated src" answer)

Fetch-at-build-time is the wrong tool: a fixed-output src pins a hash
(new source => new drv); `__impure` changes the trust model; a
sandbox=false host-path copy makes the drv no longer determine its
output. Instead, graft at consume time:

1. `git archive` the checkout, `nix store add-path` it -- pure hashing.
2. `nix derivation show target.drv`, substitute old src path -> new
   (literal split/join; store paths are exact strings).
3. Re-derive with a builtins-only expression: `appendContext` rebuilds
   the inputDrv contexts, `builtins.derivation` recomputes the
   canonical drvPath/outPath, reading the *baked* drvs for the
   modulo-hash recursion. Milliseconds; no nixpkgs. Same maneuver as
   CA derivation resolution, one hop earlier.
4. `nix-store --realise` the grafted drv.

Acceptance test: grafting the unchanged seeded src must reproduce the
baked drvPath bit-for-bit.

The graft rewrites the target drv only. Anything evaluation derived
from source *content* stays frozen: crane vendor/deps drvs (seeded
Cargo.lock), pyproject-nix's rendered dependency set, eval-computed
patches. Contract:

| checkout change                                  | outcome |
|--------------------------------------------------|---------|
| code edits                                       | graft   |
| Cargo.lock / pyproject.toml / flake.lock / deps  | re-seed |

Guard mechanically: bake hashes of the metadata files in the manifest;
refuse the graft on mismatch. This decouples seed cadence from commit
cadence: consumers re-seed on lockfile changes, graft every push.

## Projections (against measured baselines)

| | today | drvs mode |
|---|---|---|
| hello blob | 118 MB | ~65-75 MB |
| python warm job | 16 s | ~9-11 s |
| ripgrep warm job | 58 s | ~55 s (compile-bound) |

## Rollout

1. [x] `bake ? [ "sources" ]` scaffold; sources mode verified
   structurally identical (drv diff modulo hash churn).
2. [x] recipe collection via eval-time graph walk (requires `--impure`
   evaluation: the walk readFiles the instantiated drvs, which are
   content-addressed, so determinism holds). hello/innocent flipped.
   Measured: blob 118 MB -> 68.5 MB (-42%); 610 recipe files; zero
   flake-input sources; registration format-verified against
   closureInfo's records (uniform sha256:base32, parses exactly).
   Remaining: CI realise path end to end (first push exercises it).
3. [ ] src graft: guards already baked in the manifest and bin/build
   refuses src-bearing targets; next is bin/regraft (derivation show -r
   -> literal src substitution -> appendContext/builtins.derivation
   re-derivation) + the identity acceptance test (graft of the seeded
   src must reproduce the baked drvPath bit-for-bit).
4. [ ] flip remaining examples; optional `both`-mode integrity check in
   build-examples.
