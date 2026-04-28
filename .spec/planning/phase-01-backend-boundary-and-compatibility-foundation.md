# Phase 1 - Backend Boundary and Compatibility Foundation

<!-- covers: package.jido_ai.spec_led_workspace -->

Back to index: [README](README.md)

## Relevant Shared APIs / Interfaces
- `../specs/package.spec.md`
- `../specs/core_runtime_and_requests.spec.md`
- `../specs/runtime_contracts_and_observability.spec.md`
- `../specs/thread_context_projection.spec.md`
- `../specs/tooling_and_configuration.spec.md`
- `../decisions/jido_ai.llm_backend_boundary.md`
- `lib/jido_ai.ex`
- `lib/jido_ai/agent.ex`
- `lib/jido_ai/actions/helpers.ex`
- `lib/jido_ai/directive/helpers.ex`
- `lib/jido_ai/reasoning/react/config.ex`
- `lib/jido_ai/turn.ex`

## Relevant Assumptions / Defaults
- The current repo routes real LLM work through `ReqLLM`, and that remains the default backend until a second backend is implemented and proven.
- The previous-version public API surface must stay stable across this work, including entrypoint names, arities, request-handle behavior, turn contracts, and canonical runtime signals or events.
- Backend selection must be additive and explicit rather than overloading current `model_aliases` semantics or replacing `ReqLLM`-oriented config in a breaking way.
- Capability gaps must fail with structured unsupported-backend or unsupported-capability errors rather than silent fallback behavior.

[ ] 1 Phase 1 - Backend Boundary and Compatibility Foundation
  Establish the internal backend contract and compatibility rules that let `jido_ai` evolve beyond direct ReqLLM coupling without breaking the stable package surface.

  [ ] 1.1 Section - Backend Contract and Capability Model
    Define the internal backend abstraction and capability vocabulary that future ReqLLM and Harness implementations must satisfy before any runtime cutover begins.

    [ ] 1.1.1 Task - Introduce the canonical backend behaviour and request model
      Add the internal contracts that describe how Jido.AI submits generation work and receives normalized outcomes without exposing transport-specific shapes at the public boundary.

      [ ] 1.1.1.1 Subtask - Define a backend behaviour that covers synchronous generation, streaming generation, cancellation, and capability introspection through one internal interface.
      [ ] 1.1.1.2 Subtask - Define a backend-neutral request shape that can carry prompt, messages, system prompt, model, timeout, backend metadata, tool intent, and optional workspace context without assuming ReqLLM or Harness transport details.
      [ ] 1.1.1.3 Subtask - Define backend-neutral result and event shapes that can be translated into canonical Jido.AI turn, signal, and runtime-event contracts.

    [ ] 1.1.2 Task - Introduce an explicit capability contract
      Make backend limitations and supported features visible at runtime instead of inferring them from transport choice or hidden option checks.

      [ ] 1.1.2.1 Subtask - Define capability flags for text generation, streaming, structured object generation, embeddings, local tool calling, cancellation, message-history handling, and workspace-scoped execution.
      [ ] 1.1.2.2 Subtask - Define structured unsupported-capability and unsupported-backend error shapes that keep user-facing failures explicit and typed.
      [ ] 1.1.2.3 Subtask - Ensure capability checks happen before runtime execution crosses into transport-specific code so failures remain bounded and explainable.

  [ ] 1.2 Section - Additive Configuration and API Compatibility Rules
    Preserve the previous public surface while introducing additive backend controls and keeping current ReqLLM configuration valid.

    [ ] 1.2.1 Task - Define additive backend-selection configuration
      Add explicit backend selection and backend-owned configuration surfaces that do not overload or break current model-alias or llm-default semantics.

      [ ] 1.2.1.1 Subtask - Introduce a backend selection convention that defaults to ReqLLM when no alternate backend is configured.
      [ ] 1.2.1.2 Subtask - Keep current `model_aliases`, `llm_defaults`, `llm_opts`, and `req_http_options` behavior valid for the ReqLLM path while reserving distinct additive config for Harness-style execution.
      [ ] 1.2.1.3 Subtask - Define how explicit request-scoped backend overrides are expressed without changing current entrypoint names or arities.

    [ ] 1.2.2 Task - Lock down previous-version compatibility expectations
      Make the non-breaking constraints concrete enough that later phases can measure parity instead of relying on informal caution.

      [ ] 1.2.2.1 Subtask - Record the stable public entrypoints, request-handle semantics, and canonical result shapes that must remain unchanged across the migration.
      [ ] 1.2.2.2 Subtask - Record which current ReqLLM-shaped behaviors remain default semantics until a backend-specific capability or unsupported outcome is returned explicitly.
      [ ] 1.2.2.3 Subtask - Update repo-owned contributor guidance so future work treats backend evolution as an internal refactor behind stable public contracts.

  [ ] 1.3 Section - Phase 1 Integration Tests
    Verify the new backend boundary and compatibility rules exist as additive internal structure while the public API continues to behave like the previous version by default.

    [ ] 1.3.1 Task - Backend contract and capability scenarios
      Prove the new abstraction can represent the required request and capability space without leaking transport-specific details into public callers.

      [ ] 1.3.1.1 Subtask - Add coverage proving backend requests can represent prompt, message, system-prompt, timeout, and tool-intent inputs through one internal shape.
      [ ] 1.3.1.2 Subtask - Add coverage proving capability checks can reject unsupported feature combinations with structured errors before runtime execution begins.
      [ ] 1.3.1.3 Subtask - Add coverage proving ReqLLM remains the default backend when no alternate backend is selected.

    [ ] 1.3.2 Task - Public compatibility baseline scenarios
      Prove the introduction of backend selection rules does not change previous-version public entrypoint behavior by default.

      [ ] 1.3.2.1 Subtask - Add coverage proving existing facade names, arities, and default results remain unchanged under default configuration.
      [ ] 1.3.2.2 Subtask - Add coverage proving request-handle and ask or await orchestration still behave as before when the backend is not overridden.
      [ ] 1.3.2.3 Subtask - Verify the spec workspace, ADR, and package-level guidance remain coherent after the backend boundary is introduced.
