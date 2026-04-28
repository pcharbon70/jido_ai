# Jido.AI LLM Backend Evolution Plan

<!-- covers: package.jido_ai.spec_led_workspace -->

This directory contains the phased implementation plan for evolving `jido_ai`
from a ReqLLM-only execution model into a backend-normalized runtime that can
support both `ReqLLM` and `Jido.Harness` behind the stable public API surface.

The plan aligns to:
- `../specs/package.spec.md`
- `../specs/core_runtime_and_requests.spec.md`
- `../specs/runtime_contracts_and_observability.spec.md`
- `../specs/thread_context_projection.spec.md`
- `../specs/actions_and_tool_calling.spec.md`
- `../specs/strategies_and_reasoning.spec.md`
- `../specs/plugins_and_capabilities.spec.md`
- `../specs/tooling_and_configuration.spec.md`
- `../specs/security_and_error_model.spec.md`
- `../decisions/jido_ai.llm_backend_boundary.md`

## Phase Files
1. [Phase 1 - Backend Boundary and Compatibility Foundation](phase-01-backend-boundary-and-compatibility-foundation.md): establish the backend abstraction, explicit capability model, additive backend selection rules, and compatibility guardrails that preserve the previous-version public API surface.
2. [Phase 2 - Facade, Action, and ReqLLM Adapter Cutover](phase-02-facade-action-and-reqllm-adapter-cutover.md): route the existing direct facade and standalone action paths through a ReqLLM-backed adapter without changing public entrypoint names, arities, or result contracts.
3. [Phase 3 - Runtime, Turn, and Tooling Normalization](phase-03-runtime-turn-and-tooling-normalization.md): refactor directives, runtime events, turn shaping, and tool manifests so backend-specific semantics are normalized before strategy or public runtime consumers depend on them.
4. [Phase 4 - Harness Adapter and Capability-Gated Adoption](phase-04-harness-adapter-and-capability-gated-adoption.md): add the first `Jido.Harness` backend adapter, map CLI runtime events into canonical Jido.AI runtime contracts, and make unsupported capability gaps explicit and typed.
5. [Phase 5 - Strategy, Plugin, and Rollout Convergence](phase-05-strategy-plugin-and-rollout-convergence.md): adopt the backend boundary across strategy runners, capability plugins, documentation, and release-facing verification so dual-backend behavior stays explicit and non-breaking.
