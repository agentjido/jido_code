# Jido.Code Usage Rules

These rules summarize the contributor and agent expectations for `jido_code`.

## Working Model

- Treat `jido_code` as the primary product and implementation repo in this workspace.
- Run `bw prime` and `bw ready` before starting substantive work.
- Keep `.spec/` current with behavior, tests, and durable architectural decisions.
- Prefer branch and PR style collaboration for non-trivial work, even though this repo also tracks durable local state in Beadwork.

## Engineering Guardrails

- Use `Req` for HTTP calls. Do not introduce `HTTPoison`, `Tesla`, or `:httpc`.
- Do not call `String.to_atom/1` on user input.
- Do not use map-style access on structs when a proper API exists.
- Keep one module per file.
- Prefer `Task.async_stream/3` with back-pressure for concurrent enumeration.

## Phoenix And LiveView

- Start LiveView templates with `<Layouts.app ...>` when they participate in the main application shell.
- Pass `current_scope` to `<Layouts.app>` where authenticated scope is needed.
- Use Phoenix LiveView helpers (`push_navigate`, `push_patch`, `<.link navigate={...}>`, `<.link patch={...}>`) instead of deprecated redirect helpers.
- Prefer selector-based assertions in LiveView tests over raw HTML assertions.

## Standards Alignment

- Keep contributor-facing quality surfaces aligned with `docs/PACKAGE_QUALITY_ALIGNMENT.md`.
- Required root files are `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `AGENTS.md`, `LICENSE`, and this `usage-rules.md`.
- `mix quality` is the canonical standards-aligned local quality gate, and `mix q` is the shorthand entrypoint.

## Dependency-Specific Rules

When a change touches these packages, read the corresponding usage rules before editing:

- `deps/req_llm/usage-rules.md`
- `deps/jido_action/usage-rules.md`
- `deps/jido_ai/usage-rules.md`
- `deps/jido/usage-rules.md`
- `deps/ash/usage-rules.md`
- `deps/ash_postgres/usage-rules.md`
- `deps/ash_json_api/usage-rules.md`
- `deps/ash_authentication/usage-rules.md`
- `deps/ash_phoenix/usage-rules.md`
- `deps/ash_typescript/usage-rules.md`
- `deps/phoenix/usage-rules/`
