# Ontology

The GameChanger protocol model is also shipped as an **RDF ontology**
and an **instance graph**, so the same concepts described in the
[protocol](./protocol.md), [integration](./integration.md), and
[security](./security.md) pages can be explored visually.

## Viewing the graph

Open the graph view:

<https://lambdasistemi.github.io/graph-browser/?repo=lambdasistemi/haskell-gamechanger>

[graph-browser](https://github.com/lambdasistemi/graph-browser) loads
`data/config.json` and the Turtle files in `data/rdf/` from this
repository on `main`, and renders them as an interactive node-link
diagram with tutorials.

## Files

| Path | Content |
|---|---|
| [`data/config.json`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/data/config.json) | Graph-browser manifest — kinds, graph sources, display metadata |
| [`data/rdf/core-ontology.ttl`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/data/rdf/core-ontology.ttl) | graph-browser core vocabulary (reused) — `gb:Dataset`, `gb:Node`, `gb:EdgeReference`, etc. |
| [`data/rdf/gamechanger-ontology.ttl`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/data/rdf/gamechanger-ontology.ttl) | **The GameChanger ontology** — domain classes (`gc:Script`, `gc:Export`, `gc:Wallet`, …), properties, and hierarchies |
| [`data/rdf/graph.ttl`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/data/rdf/graph.ttl) | A worked instance graph — a concrete example of the *backend-callback* topology with its actors, script, exports, and trust boundaries |

## Why an ontology

Three reasons:

1. **Unambiguous communication.** Prose in docs can drift. A
   `gc:Export gc:mode "post"` triple cannot.
2. **Graph-browser integration.** Browsable node-link view of the
   protocol — useful for onboarding and for spotting structural
   holes in the model.
3. **Machine tooling.** Later, we can generate Haskell types from
   SHACL/OWL constraints, validate scripts against the ontology, and
   publish the vocabulary at stable `lambdasistemi.github.io/haskell-gamechanger/vocab/...`
   IRIs.

## Namespace

The GameChanger vocabulary lives under:

```
https://lambdasistemi.github.io/haskell-gamechanger/vocab/terms#
```

with the prefix `gc:` in Turtle files. It imports the
graph-browser core vocabulary:

```
https://lambdasistemi.github.io/graph-browser/vocab/ontology
```

so that GameChanger classes inherit from `gb:Node` and can be
displayed by graph-browser's `kinds` system.

## Keeping it consistent

Per the [constitution's §10 governance clause](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md#governance),
any change to the protocol model must update the constitution, the
docs, and the ontology **in the same commit**. A three-way drift
would make the repository actively misleading.
