# Jido OS Runtime Compatibility

This subject defines the repo-local `jido_os` compatibility package that keeps
the coding-assistance wrapper self-contained in `jido_code`.

```spec-meta
id: jido_os.runtime.compatibility
kind: feature
status: active
summary: jido_code provides a version-controlled local jido_os compatibility package that satisfies the public runtime, session, and coding-assistance APIs used by the coding-assistance boundary without requiring a sibling workspace checkout in CI.
surface:
  - mix.exs
  - compat/jido_os/mix.exs
  - compat/jido_os/lib/**/*.ex
  - test/jido_code/coding_assistance_test.exs
```

## Requirements

```spec-requirements
- id: jido_os.runtime.compatibility.local_override_present
  statement: jido_code shall satisfy its `:jido_os` dependency from a version-controlled repo-local compatibility package so CI and contributors do not need a separate sibling checkout just to compile the coding-assistance boundary.
  priority: must
  stability: evolving

- id: jido_os.runtime.compatibility.public_runtime_surface
  statement: The compatibility package shall expose the public `Jido.Os` runtime, session, directory, and coding-assistance modules that `JidoCode.JidoOsRuntime` and `JidoCode.CodingAssistance` call.
  priority: must
  stability: evolving

- id: jido_os.runtime.compatibility.session_and_envelope_behaviour
  statement: The compatibility package shall support instance bootstrap, session creation/loading, project binding, AI-preference updates, and typed coding-assistance envelopes for the wrapper test surface.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: mix.exs
  covers:
    - jido_os.runtime.compatibility.local_override_present

- kind: source_file
  target: compat/jido_os/lib/jido/os/system_instance_supervisor.ex
  covers:
    - jido_os.runtime.compatibility.public_runtime_surface
    - jido_os.runtime.compatibility.session_and_envelope_behaviour

- kind: source_file
  target: compat/jido_os/lib/jido/os/session/runtime_agent.ex
  covers:
    - jido_os.runtime.compatibility.public_runtime_surface
    - jido_os.runtime.compatibility.session_and_envelope_behaviour

- kind: source_file
  target: compat/jido_os/lib/jido/os/coding_assist/service.ex
  covers:
    - jido_os.runtime.compatibility.public_runtime_surface
    - jido_os.runtime.compatibility.session_and_envelope_behaviour

- kind: source_file
  target: test/jido_code/coding_assistance_test.exs
  covers:
    - jido_os.runtime.compatibility.local_override_present
    - jido_os.runtime.compatibility.public_runtime_surface
    - jido_os.runtime.compatibility.session_and_envelope_behaviour

- kind: command
  target: mix test test/jido_code/coding_assistance_test.exs
  covers:
    - jido_os.runtime.compatibility.local_override_present
    - jido_os.runtime.compatibility.public_runtime_surface
    - jido_os.runtime.compatibility.session_and_envelope_behaviour
```
