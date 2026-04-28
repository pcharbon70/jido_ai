# Phase 2 - Facade, Action, and ReqLLM Adapter Cutover

<!-- covers: package.jido_ai.spec_led_workspace -->

Back to index: [README](README.md)

## Relevant Shared APIs / Interfaces
- `../specs/core_runtime_and_requests.spec.md`
- `../specs/actions_and_tool_calling.spec.md`
- `../specs/tooling_and_configuration.spec.md`
- `../specs/security_and_error_model.spec.md`
- `../decisions/jido_ai.llm_backend_boundary.md`
- `lib/jido_ai.ex`
- `lib/jido_ai/actions/helpers.ex`
- `lib/jido_ai/actions/llm/*.ex`
- `lib/jido_ai/actions/planning/*.ex`
- `lib/jido_ai/actions/reasoning/*.ex`
- `lib/jido_ai/actions/tool_calling/call_with_tools.ex`
- `lib/jido_ai/model_aliases.ex`

## Relevant Assumptions / Defaults
- Phase 1 has already established a backend-neutral request, result, and capability model.
- ReqLLM is still the canonical default backend and must preserve current facade, action, and error behavior while the internal call path changes.
- Structured object generation and embeddings remain supported through ReqLLM in this phase and should not be redefined through fake compatibility shims.
- Public callers should continue to use existing facade functions and standalone actions without needing to know a backend abstraction was introduced.

[ ] 2 Phase 2 - Facade, Action, and ReqLLM Adapter Cutover
  Route existing direct facade and standalone action surfaces through a ReqLLM-backed adapter so the first backend abstraction lands without changing public API behavior.

  [ ] 2.1 Section - ReqLLM Backend Adapter Implementation
    Build the first concrete backend implementation by translating the new backend-neutral request shape into the current ReqLLM runtime behavior.

    [ ] 2.1.1 Task - Implement the canonical ReqLLM backend adapter
      Add the adapter that owns model resolution, ReqLLM option shaping, synchronous generation, streaming generation, object generation, and embeddings for the default backend path.

      [ ] 2.1.1.1 Subtask - Translate backend-neutral text and streaming requests into the current ReqLLM generation and stream calls without changing option semantics.
      [ ] 2.1.1.2 Subtask - Translate structured-object and embedding requests into ReqLLM-specific calls while keeping those capabilities explicitly marked as ReqLLM-supported.
      [ ] 2.1.1.3 Subtask - Normalize ReqLLM success and failure outcomes back into the backend-neutral result model instead of letting raw ReqLLM structs escape above the adapter boundary.

    [ ] 2.1.2 Task - Centralize ReqLLM-specific option shaping inside the adapter
      Remove scattered ReqLLM request assembly where possible so later backend work does not require duplicating facade and action logic.

      [ ] 2.1.2.1 Subtask - Move current model, timeout, temperature, max-token, and `req_http_options` shaping into the ReqLLM adapter path or its immediate helpers.
      [ ] 2.1.2.2 Subtask - Keep `model_aliases` and `llm_defaults` behavior intact while making the backend-neutral request assembly explicit above the adapter.
      [ ] 2.1.2.3 Subtask - Preserve sanitized, typed error behavior for callers even though the underlying transport is now reached through the adapter.

  [ ] 2.2 Section - Public Facade and Standalone Action Adoption
    Cut the current top-level facade and standalone action surfaces over to the adapter path while keeping their public contracts stable.

    [ ] 2.2.1 Task - Route top-level LLM facades through the backend boundary
      Make `generate_text`, `generate_object`, `stream_text`, and `ask` use the new backend interface while preserving current defaults and return contracts.

      [ ] 2.2.1.1 Subtask - Keep current entrypoint names, arities, and default model-selection behavior unchanged for public callers.
      [ ] 2.2.1.2 Subtask - Keep current message normalization and system-prompt handling behavior stable even though the final transport call moves behind the adapter.
      [ ] 2.2.1.3 Subtask - Preserve current ReqLLM-oriented streaming return behavior for the default backend path until a later phase widens runtime normalization.

    [ ] 2.2.2 Task - Route standalone AI actions through the backend boundary
      Make the existing LLM, planning, and lightweight reasoning actions depend on the backend interface rather than calling ReqLLM directly.

      [ ] 2.2.2.1 Subtask - Refactor shared action helpers so they assemble backend-neutral requests instead of transport-specific calls.
      [ ] 2.2.2.2 Subtask - Cut `Actions.LLM.*`, planning actions, and prompt-oriented reasoning actions over to the ReqLLM adapter without changing their public params or result shapes.
      [ ] 2.2.2.3 Subtask - Keep tool-calling actions working on the ReqLLM path while deferring backend-neutral tool manifest work to a later runtime phase.

  [ ] 2.3 Section - Phase 2 Integration Tests
    Verify the ReqLLM adapter path preserves previous facade and standalone-action behavior while centralizing transport-specific execution behind the new backend boundary.

    [ ] 2.3.1 Task - Top-level facade parity scenarios
      Prove the public direct LLM facades still behave like the previous version under default configuration after the internal cutover.

      [ ] 2.3.1.1 Subtask - Add coverage proving text generation, structured object generation, and ask helpers preserve current names, arities, defaults, and result shapes.
      [ ] 2.3.1.2 Subtask - Add coverage proving streaming calls still produce the current ReqLLM-shaped default path for callers that depend on it.
      [ ] 2.3.1.3 Subtask - Add coverage proving current model-alias and llm-default configuration continues to work unchanged through the adapter.

    [ ] 2.3.2 Task - Standalone action parity scenarios
      Prove standalone actions still deliver the same user-facing behavior while the direct ReqLLM calls are moved behind the adapter.

      [ ] 2.3.2.1 Subtask - Add coverage proving chat, complete, generate-object, and embed actions still return the previous normalized results under the ReqLLM path.
      [ ] 2.3.2.2 Subtask - Add coverage proving planning and prompt-oriented reasoning actions still work through the shared adapter boundary without public parameter changes.
      [ ] 2.3.2.3 Subtask - Verify the current docs and spec workspace remain coherent after the ReqLLM adapter becomes the default execution seam.
