# haskell-gamechanger

Haskell client for the [GameChanger](https://gamechanger.finance/)
Cardano wallet — script DSL, URL encoding, callback handling.

**Status: understanding phase.** The repository currently ships no
Haskell code. Its first output is a reference model of the GameChanger
protocol: a [constitution](./.specify/memory/constitution.md),
a [MkDocs site](./docs/), and an
[RDF ontology](./data/rdf/) viewable through
[graph-browser](https://github.com/lambdasistemi/graph-browser).
A Haskell implementation follows once the model is stable.

## Read

- [Constitution](./.specify/memory/constitution.md) — source of truth
- [Docs site](https://lambdasistemi.github.io/haskell-gamechanger/) — once deployed
- [Graph view](https://lambdasistemi.github.io/graph-browser/?repo=lambdasistemi/haskell-gamechanger) — once deployed
- [Security](./docs/security.md)

## Develop

```bash
nix develop       # mkdocs + just
just build-docs   # strict build
just serve-docs   # local preview at :8000
```
