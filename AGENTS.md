# AGENTS.md

## Mission

Implement and evolve `jido_code` as the primary product and implementation repo in this workspace.

<!-- covers: package.jido_code.primary_implementation_repo -->

`jido_os` is an upstream/runtime-contract helper repo. `jido_ecosystem` is reference material for governance behavior that will eventually migrate here. Default to working in `jido_code`.

## First Read

1. Run `bw prime`.
2. Run `bw ready`.
3. Read `.spec/README.md`.
4. Read `.spec/AGENTS.md`, `.spec/specs/*.spec.md`, and `.spec/decisions/*.md`.
5. Read the relevant code, routes, and tests before changing behavior.
6. For non-trivial work, prefer a branch and pull request instead of changes that would land directly on `main`.

## Work Management

<!-- covers: collaboration.workflow.beadwork_enabled collaboration.workflow.github_prs -->

This repo uses `bw` (beadwork) for durable local agent work state.

- ALWAYS run `bw prime` before starting work.
- Run `bw ready` after priming so work starts from the current local queue instead of ad hoc task selection.
- Use `bw create`, `bw ready`, `bw start`, `bw comment`, `bw close`, and `bw sync` to keep local work state durable.
- Beadwork is local execution state, not the only collaboration record. For shared work, discovered bugs, and meaningful feature changes, prefer GitHub issues and pull requests.
- Do not land work directly on `main`. Use a branch + PR flow for collaboration.

## Spec Led Development

<!-- covers: package.jido_code.spec_led_workspace -->

`.spec/` is the package-local Spec Led Development workspace for current-truth specs and durable ADRs.

- Keep specs current with code and tests.
- Keep one subject per file under `.spec/specs/*.spec.md`.
- Use `.spec/decisions/*.md` only for durable cross-cutting ADRs.
- Use Git history and pull requests as the time dimension. Keep `.spec` current-state only.
- Prefer updating specs before or alongside implementation.
- If spec tooling is blocked by an unrelated compile/runtime failure, report the blocker clearly instead of inventing a passing result.

Useful commands:

```bash
mix spec.prime --base HEAD
mix spec.next
mix spec.check --base origin/main
mix spec.status
mix spec.decision.new <slug> --title "Decision title"
```

## Engineering Guardrails

### Elixir and Phoenix

- Use `Req` for HTTP calls. Do not introduce `HTTPoison`, `Tesla`, or `:httpc`.
- Do not use `String.to_atom/1` on user input.
- Do not use map-access syntax on structs (`changeset[:field]`); use struct fields or APIs like `Ecto.Changeset.get_field/2`.
- Keep one module per file.
- Prefer `Task.async_stream/3` with back-pressure for concurrent enumeration.

### LiveView and HEEx

- Start LiveView templates with `<Layouts.app flash={@flash} ...>`.
- Pass `current_scope` to `<Layouts.app>` where authenticated scope is needed.
- Never call `<.flash_group>` outside the layouts module.
- Use `<.input>` from core components for forms when available.
- Use `<.icon>` for hero icons.
- Use HEEx-compatible interpolation and class list syntax.
- Do not use deprecated `live_redirect`/`live_patch`; use `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate`, `push_patch`.
- Prefer LiveView streams for collection rendering and updates.

### LiveVue

- Keep the routed page shell in LiveView. Use Vue only for bounded richer regions.
- Mount Vue-backed regions through `<.vue_surface ...>` instead of raw `<.vue ...>` calls.
- Keep server-authored state bounded in `props:` or `streams:` and route Vue emits back into LiveView events.
- If a hybrid surface degrades, keep the operator experience in product-oriented compatibility mode rather than surfacing raw Vite, SSR, or manifest failures.
- When touching `live_vue`, Vite, SSR entrypoints, or shared browser helpers, run `mix frontend.verify`.

### JS and CSS

- Tailwind v4 import style in `assets/css/app.css` must stay:
  - `@import "tailwindcss" source(none);`
  - `@source "../css";`
  - `@source "../js";`
  - `@source "../../lib/jido_code_web";`
- Do not use inline `<script>` tags in HEEx.
- For LiveView hooks, use colocated hooks (`<script :type={Phoenix.LiveView.ColocatedHook}>`) or registered external hooks.

### Testing

- Use `start_supervised!/1` for supervised processes in tests.
- Avoid `Process.sleep/1`; use monitor/assert patterns or `:sys.get_state/1` synchronization.
- For LiveView tests, use `Phoenix.LiveViewTest` helpers (`element/2`, `has_element?/2`, `render_submit/2`, `render_change/2`) and stable DOM IDs.
- Do not assert raw full HTML when selector-based assertions are possible.

## Dependency Usage Rules

When touching these packages, consult usage rules first:

- `deps/req_llm/usage-rules.md`
- `deps/jido_action/usage-rules.md`
- `deps/jido_ai/usage-rules.md`
- `deps/jido/usage-rules.md`
- `deps/ash/usage-rules.md`
- `deps/ash_postgres/usage-rules.md`
- `deps/ash_json_api/usage-rules.md`
- `deps/ash_authentication/usage-rules.md`
- `deps/ash_phoenix/usage-rules.md`
- `deps/phoenix/usage-rules/`
