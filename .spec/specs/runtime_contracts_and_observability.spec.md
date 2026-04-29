# Runtime Contracts And Observability

Current-truth contract for strategy/runtime layering, directives, signals, runtime events, and telemetry boundaries.

```spec-meta
id: jido_ai.runtime_contracts
kind: contract
status: active
summary: Runtime execution keeps strategy, directives, side effects, signals, and telemetry as explicit layers with canonical envelopes and event names.
decisions:
  - jido_ai.llm_backend_boundary
surface:
  - lib/jido_ai/backend.ex
  - lib/jido_ai/backend/*.ex
  - lib/jido_ai/directive/*.ex
  - lib/jido_ai/runtime/*.ex
  - lib/jido_ai/signals/*.ex
  - lib/jido_ai/observe.ex
  - lib/jido_ai/pending_input_server.ex
  - lib/jido_ai/reasoning/react/event.ex
  - lib/jido_ai/reasoning/react/pending_input.ex
  - lib/jido_ai/reasoning/react/signal.ex
  - guides/developer/architecture_and_runtime_flow.md
  - guides/developer/directives_runtime_contract.md
  - guides/developer/signals_namespaces_contracts.md
  - guides/user/observability_basics.md
```

## Requirements

```spec-requirements
- id: jido_ai.runtime_contracts.layered_runtime_flow
  statement: Runtime flow shall keep strategy policy, directive intent, side-effect execution, and signal routing as explicit layers so bugs can be fixed at the correct boundary.
  priority: must
  stability: stable

- id: jido_ai.runtime_contracts.directive_signal_envelopes
  statement: Directives shall emit standardized request, llm, tool, and embed signal/result envelopes with explicit correlation, retry, and timeout semantics.
  priority: must
  stability: stable

- id: jido_ai.runtime_contracts.backend_normalization_boundary
  statement: Backend-specific provider, CLI session, tool, and stream semantics shall be normalized into canonical Jido.AI directives, signals, runtime events, and turn inputs before strategy logic or public runtime consumers depend on them, including directive request building, canonical tool manifests, and stream-progress translation for ai.llm and ai.embed runtime paths.
  priority: must
  stability: evolving

- id: jido_ai.runtime_contracts.canonical_signals_and_telemetry
  statement: Canonical signal namespaces and telemetry event paths shall stay stable across strategies, runtime, and tooling, with normalized metadata and measurements.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/architecture_and_runtime_flow.md
  covers:
    - jido_ai.runtime_contracts.layered_runtime_flow

- kind: guide_file
  target: guides/developer/directives_runtime_contract.md
  covers:
    - jido_ai.runtime_contracts.directive_signal_envelopes

- kind: source_file
  target: .spec/decisions/jido_ai.llm_backend_boundary.md
  covers:
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/backend.ex
  covers:
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/backend/request.ex
  covers:
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/backend/result.ex
  covers:
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/directive/helpers.ex
  covers:
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/directive/llm_generate.ex
  covers:
    - jido_ai.runtime_contracts.directive_signal_envelopes
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/directive/llm_stream.ex
  covers:
    - jido_ai.runtime_contracts.directive_signal_envelopes
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: source_file
  target: lib/jido_ai/directive/llm_embed.ex
  covers:
    - jido_ai.runtime_contracts.directive_signal_envelopes
    - jido_ai.runtime_contracts.backend_normalization_boundary

- kind: guide_file
  target: guides/developer/signals_namespaces_contracts.md
  covers:
    - jido_ai.runtime_contracts.canonical_signals_and_telemetry

- kind: guide_file
  target: guides/user/observability_basics.md
  covers:
    - jido_ai.runtime_contracts.canonical_signals_and_telemetry
```
