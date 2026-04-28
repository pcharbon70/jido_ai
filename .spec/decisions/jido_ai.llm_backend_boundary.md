---
id: jido_ai.llm_backend_boundary
status: accepted
date: 2026-04-28
affects:
  - package.jido_ai
  - jido_ai.core_runtime
  - jido_ai.runtime_contracts
  - jido_ai.thread_context_projection
---

# Jido.AI LLM Backend Boundary And API Compatibility

<!-- covers: package.jido_ai.explicit_policy_boundaries package.jido_ai.public_api_surface_compatibility jido_ai.core_runtime.llm_facades jido_ai.core_runtime.additive_backend_selection jido_ai.runtime_contracts.backend_normalization_boundary jido_ai.thread_context_projection.turn_normalization -->

## Context

`jido_ai` currently routes its LLM-facing behavior through `ReqLLM`, and its
public package surface is shaped around stable facades, actions, directives,
request handles, signals, runtime events, and normalized turns.

We want to support both `ReqLLM` and `Jido.Harness`-style execution behind the
same package over time, but those systems do not expose the same raw transport
shapes. `ReqLLM` is model/message/tool-call oriented. `Jido.Harness` is
provider/session/event oriented and is optimized for CLI coding-agent
execution.

That means backend support cannot be introduced by simply swapping one raw
transport for another at the public API boundary.

## Decision

Jido.AI shall treat LLM execution as an internal backend boundary rather than a
public transport contract.

ReqLLM remains the default backend for current provider/model integrations and
for the feature-complete paths that already depend on its model, response,
streaming, embedding, and tool-call semantics.

Additional backends, including `Jido.Harness`, may be added only through
explicit backend adapters behind the existing request-bearing surfaces.

Cross-cutting backend evolution shall preserve the previous-version public API
surface. Current public entrypoint names, arities, canonical return shapes,
request-handle behavior, and signal/runtime-event contracts must remain stable
while backend support expands.

Backend selection must be additive and explicit. Jido.AI must not rename or
replace the existing public request APIs just to expose a new transport or
runtime.

The additive selection convention is:

- app default under `config :jido_ai, llm_backend: ...`
- backend-owned additive config under `config :jido_ai, llm_backends: %{...}`
- request-scoped override through existing public entrypoints with
  `backend: :req_llm | ...`

These controls reserve alternate backends without overloading the existing
`model_aliases`, `llm_defaults`, `llm_opts`, or `req_http_options` semantics
that continue to belong to the ReqLLM path.

Backend-specific provider, CLI session, tool, and stream semantics must be
normalized before they cross into public Jido.AI turn, request, signal, or
runtime-event contracts.

Capability gaps are explicit. If a backend cannot support a required contract
such as embeddings, structured object generation, local tool calling, or some
other existing stable surface, Jido.AI shall fail with a structured
unsupported-capability error rather than silently degrading the contract.

Model aliases and current ReqLLM-facing configuration remain supported. Any
alternate backend or provider selection must be additive rather than overloading
the current alias/config semantics in a breaking way.

Until a non-ReqLLM backend is implemented for a given call path, explicit
selection of that backend shall return a structured unsupported-backend or
unsupported-capability outcome instead of silently falling back to ReqLLM.

## Consequences

Jido.AI can introduce a backend abstraction incrementally without forcing a
breaking rewrite of the package surface first.

ReqLLM-centric code paths can remain in place while request, directive, action,
and runtime boundaries are refactored toward backend normalization.

The first concrete backend adapter should be ReqLLM-backed so existing public
facades and standalone actions can move behind the backend seam before any
alternate backend changes public runtime behavior.

When those cutovers happen, top-level facades should keep their historical raw
ReqLLM-shaped default return values, and standalone actions should keep their
historical normalized result maps even though transport execution now routes
through the backend adapter.

`Jido.Harness` integration should begin where prompt/cwd/session semantics are a
natural fit, rather than forcing every existing ReqLLM-shaped surface to become
immediately dual-backed.

Future spec and code changes that widen backend support should update the
normalization boundaries and capability contracts instead of creating
backend-specific public APIs that fragment the package surface.
