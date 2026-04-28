# Core Runtime And Requests

Current-truth contract for top-level Jido.AI runtime entrypoints and request-handle orchestration.

```spec-meta
id: jido_ai.core_runtime
kind: runtime
status: active
summary: Public runtime entrypoints expose direct LLM facades, a default ReAct-first agent macro, and request-handle orchestration for concurrent AI work while backend execution stays behind stable request contracts.
decisions:
  - jido_ai.llm_backend_boundary
surface:
  - lib/jido_ai.ex
  - lib/jido_ai/agent.ex
  - lib/jido_ai/backends.ex
  - lib/jido_ai/backends/*.ex
  - lib/jido_ai/backend/request.ex
  - lib/jido_ai/request.ex
  - lib/jido_ai/request/*.ex
  - lib/jido_ai/model_aliases.ex
  - lib/jido_ai/prompt_builder.ex
  - guides/user/getting_started.md
  - guides/user/first_react_agent.md
  - guides/user/llm_facade_quickstart.md
  - guides/user/request_lifecycle_and_concurrency.md
  - guides/user/package_overview.md
```

## Requirements

```spec-requirements
- id: jido_ai.core_runtime.llm_facades
  statement: Jido.AI shall expose direct LLM facade entrypoints with explicit model alias resolution and merged runtime defaults for text, object, and streaming generation, while backend execution changes stay behind those stable entrypoint contracts.
  priority: must
  stability: stable

- id: jido_ai.core_runtime.additive_backend_selection
  statement: Backend selection for request-bearing entrypoints shall remain additive and explicit rather than replacing the current ask, await, generate, or stream API surface.
  priority: must
  stability: evolving

- id: jido_ai.core_runtime.react_agent_entrypoint
  statement: Jido.AI.Agent shall remain the default ReAct-first long-lived agent surface with explicit ask/await/ask_sync orchestration and request-scoped runtime overrides.
  priority: must
  stability: stable

- id: jido_ai.core_runtime.request_handles
  statement: Request tracking shall isolate concurrent runs through per-request handles, status correlation, streaming sinks, and await semantics instead of a single mutable result slot.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/user/llm_facade_quickstart.md
  covers:
    - jido_ai.core_runtime.llm_facades

- kind: source_file
  target: .spec/decisions/jido_ai.llm_backend_boundary.md
  covers:
    - jido_ai.core_runtime.llm_facades
    - jido_ai.core_runtime.additive_backend_selection

- kind: source_file
  target: lib/jido_ai/backend/request.ex
  covers:
    - jido_ai.core_runtime.additive_backend_selection

- kind: source_file
  target: lib/jido_ai/backends.ex
  covers:
    - jido_ai.core_runtime.additive_backend_selection

- kind: guide_file
  target: guides/user/first_react_agent.md
  covers:
    - jido_ai.core_runtime.react_agent_entrypoint

- kind: guide_file
  target: guides/user/request_lifecycle_and_concurrency.md
  covers:
    - jido_ai.core_runtime.request_handles
```
