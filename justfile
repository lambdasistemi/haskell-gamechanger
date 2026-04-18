default:
    @just --list

build-docs:
    mkdocs build --strict

serve-docs:
    mkdocs serve

deploy-docs:
    mkdocs gh-deploy --force

ci: build-docs
