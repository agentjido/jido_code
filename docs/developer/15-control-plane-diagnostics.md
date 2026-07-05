# Control-Plane Diagnostics

The embedded control-plane store is the product data plane. Prefer product
query helpers for normal work. Use diagnostic queries only when you are
checking store health, graph counts, or a bounded record projection.

## Safe Queries

```bash
mix control_plane.query --named health
mix control_plane.query --named graph-counts
mix control_plane.query --named list-records --record-type managed_repo --limit 25 --json
```

Safe queries use product-owned projection helpers and avoid exposing raw graph
details by default.

## Raw SPARQL

Raw SPARQL is gated and bounded:

```bash
mix control_plane.query --sparql 'SELECT ?s WHERE { GRAPH <https://jido.run/graphs/control_plane> { ?s ?p ?o } }' --allow-raw --graph control_plane --limit 25 --timeout 5000 --json
```

Use explicit graph IRIs in the query and pass the matching `--graph` allow-list.
Auth and security graph diagnostics are redacted by the query boundary.
