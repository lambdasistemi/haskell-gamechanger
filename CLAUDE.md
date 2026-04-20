# CLAUDE.md — haskell-gamechanger

Repository bootstrap for Claude Code sessions.

## Context

- **Scope**: backend-only Haskell library for the GameChanger browser
  wallet. No browser / WASM target. See
  [docs/scope.md](./docs/scope.md).
- **Encoding**: the Intent eDSL uses `Control.Monad.Operational`. No
  final-tagless / typeclass-indexed encodings. See
  [constitution §11](./.specify/memory/constitution.md).

## Workflow

- Every ticket goes through speckit: `/speckit.specify` →
  `/speckit.plan` → `/speckit.tasks` → `/speckit.implement`.
- Load the `workflow` skill at the start of any coding session here.
- Any change to protocol model updates **constitution + docs +
  ontology** in one vertical commit (governance rule).

## Build

- `nix develop` enters the dev shell.
- `just ci` runs the full local gate (build + test + format-check +
  hlint).
- CI on `nixos` self-hosted runners via the Build Gate pattern.

## Links

- [Constitution](./.specify/memory/constitution.md)
- [Scope](./docs/scope.md)
- [Intent eDSL](./docs/intent-dsl.md)
- [Issue tracker](https://github.com/lambdasistemi/haskell-gamechanger/issues)
