default:
    @just --list

# Haskell

build:
    cabal build all -O0

test:
    nix run .#tests

format:
    fourmolu -i $(find src app test -name '*.hs')
    cabal-fmt -i haskell-gamechanger.cabal

format-check:
    fourmolu -m check $(find src app test -name '*.hs')
    cabal-fmt -c haskell-gamechanger.cabal

hlint:
    hlint src app test

lint:
    nix run .#lint

ci: build test format-check hlint

# Docs

build-docs:
    mkdocs build --strict

serve-docs:
    mkdocs serve

deploy-docs:
    mkdocs gh-deploy --force
