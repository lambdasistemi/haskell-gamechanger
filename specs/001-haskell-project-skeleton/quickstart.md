# Quickstart — contributing to haskell-gamechanger

Target audience: a contributor starting a downstream Scope A ticket (#6–#14) or a reviewer verifying the skeleton works end-to-end.

## One-time setup

```bash
git clone git@github.com:lambdasistemi/haskell-gamechanger.git
cd haskell-gamechanger
direnv allow          # optional — auto-enters nix develop
```

No local Haskell install needed. Everything runs through `nix develop`.

## Daily loop

Enter the dev shell:

```bash
nix develop --quiet
```

Build, test, and run the gate:

```bash
just build         # cabal build all
just test          # run the tasty suite
just ci            # build + test + format-check + hlint — same as CI
```

Format code in place:

```bash
just format        # fourmolu -i + cabal-fmt -i
```

Run `hgc`:

```bash
nix run .#hgc -- --version
# or
cabal run hgc -- --version
```

## Adding a new module

Let's walk through what ticket #6 will do — adding `GameChanger.Script`:

1. Create `src/GameChanger/Script.hs` with your module body.
2. Add `GameChanger.Script` to the `exposed-modules:` list in `haskell-gamechanger.cabal`.
3. Run `just build` to confirm it compiles.
4. Add tests under `test/` and extend `test/Spec.hs` if you want a new test group.
5. Run `just ci` to confirm the full gate passes.

No flake, justfile, or CI edits are required to add a module. That is the skeleton's contract (spec SC-004).

## Adding a dependency

1. Add the package to the `build-depends:` list of the cabal stanza that needs it (library, exe, or test).
2. If the package is on Hackage, nothing else is needed — the `index-state` in `cabal.project` pins the Hackage view.
3. If the package is on CHaP (Cardano Haskell Packages) — e.g. `cardano-api` — add it under `source-repository-package` if needed; otherwise it is already resolvable via the CHaP input in `flake.nix`.
4. Run `just build`. If `haskell.nix` complains about a missing plan, run `nix flake update` to refresh the inputs.

## CI mental model

```
build-gate ──▶ tests
           └─▶ lint
```

`build-gate` runs first and builds every check derivation and every dev-shell input, warming the shared Nix store on the self-hosted runner. The `tests` and `lint` jobs then run `nix run .#tests` and `nix run .#lint` against a warm store, so they are typically seconds rather than minutes.

If `build-gate` fails, no fan-out jobs run. Fix the build first.

## Common pitfalls

- **Running `just` outside `nix develop`** — the recipes assume fourmolu, hlint, cabal-fmt, and cabal are on PATH. Either enter the shell (`nix develop`) or prefix with `nix develop -c`.
- **`nix develop -c` does not run `shellHook`** — env vars set in the hook are unavailable. Do not rely on them inside recipes.
- **Stale cache after bumping GHC** — delete `dist-newstyle/` and re-run `just build`.
- **Local fourmolu version ≠ CI** — do not install fourmolu globally; use the one from the dev shell. Pinned in `flake.nix`.

## Verifying the skeleton from scratch

This is what a reviewer runs to accept ticket #5:

```bash
git checkout feat/issue-5-skeleton
nix flake show                                      # lists expected outputs
nix develop -c just ci                              # full local gate
nix build .#checks.x86_64-linux.{library,exe,tests,lint}
nix run .#hgc -- --version
```

All five commands should complete without error.

## Further reading

- [Constitution](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md)
- [Scope](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/docs/scope.md)
- [Intent eDSL](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/docs/intent-dsl.md)
- Ticket backlog: [#5–#14](https://github.com/lambdasistemi/haskell-gamechanger/issues?q=is%3Aissue+is%3Aopen+label%3Afeat%2Cchore%2Cci)
