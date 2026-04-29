---
id: jido_ai.llm_backend_boundary
status: accepted
date: 2026-04-28
affects:
  - package.jido_ai
  - jido_ai.core_runtime
  - jido_ai.runtime_contracts
  - jido_ai.strategies
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

Canonical tool descriptions must likewise be normalized before transport
conversion. Jido-owned action metadata, parameter schemas, and tool lookup
should flow through backend-neutral tool manifests, with ReqLLM tool structs
treated as adapter output rather than the internal source of truth.

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

The first additive `Jido.Harness` adoption slice is bounded:

- direct facades remain ReqLLM-only
- compatible prompt-plus-workspace directive, request, and standalone ReAct runtime paths may opt into Harness explicitly
- unsupported Harness capabilities such as embeddings, structured objects, local Jido tool execution, and unreduced message history remain typed failures

Later capability-plugin and strategy adoption follows the same asymmetry:

- standalone Chat and Planning actions plus compatible plugin routes may surface additive `backend`, `workspace`, and `backend_metadata` inputs without changing route names or normalized result maps
- tool-calling routes may surface the same additive inputs, but alternate backends must fail explicitly until they can satisfy the local Jido tool-loop contract
- per-strategy reasoning plugins and `RunStrategy` remain ReqLLM-default and capability-gated until each underlying strategy runtime is normalized beyond transport-specific streaming or message-history assumptions

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

Directive execution and standalone ReAct runtime flow should move behind the
same backend request and backend event boundary before any alternate backend is
introduced for those paths. When that happens, canonical `ai.llm.*`,
`ai.embed.*`, and ReAct runtime event names, correlation fields, timeout
behavior, and cancellation semantics must remain stable even though backend
stream callbacks are translated underneath them.

Canonical turn shaping should accept normalized backend result maps and
canonical tool-call records directly. ReqLLM response structs remain supported,
but they should no longer be required at the point where Jido.AI decides
whether a turn is a final answer, a tool loop, or a follow-up message
projection.

`Jido.Harness` integration should begin where prompt/cwd/session semantics are a
natural fit, rather than forcing every existing ReqLLM-shaped surface to become
immediately dual-backed.

That means early Harness adoption is intentionally asymmetric. The package may
support Harness on compatible request-bearing runtime paths before it supports
the top-level facades or ReqLLM-specific capabilities, as long as those gaps
stay explicit and non-breaking.

Future spec and code changes that widen backend support should update the
normalization boundaries and capability contracts instead of creating
backend-specific public APIs that fragment the package surface.

Contributor docs, package guides, and repo-owned backend-matrix test helpers
must stay aligned with that contract. Documentation should state which paths
remain ReqLLM-default, which can opt into Harness, and which stay typed
unsupported, while verification helpers should make those compatibility
assertions repeatable without re-encoding backend env setup in each test.

When a public action is already prompt-oriented, widening backend support
should prefer canonical `prompt` / `system_prompt` / `workspace` request
shaping over reconstructing alternate backends from ReqLLM-specific message
lists. That keeps ReqLLM parity intact while making compatible alternate
backends executable instead of merely configurable.
