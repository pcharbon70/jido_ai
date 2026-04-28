# Phase 4 - Harness Adapter and Capability-Gated Adoption

<!-- covers: package.jido_ai.spec_led_workspace -->

Back to index: [README](README.md)

## Relevant Shared APIs / Interfaces
- `../specs/core_runtime_and_requests.spec.md`
- `../specs/runtime_contracts_and_observability.spec.md`
- `../specs/thread_context_projection.spec.md`
- `../specs/security_and_error_model.spec.md`
- `../specs/tooling_and_configuration.spec.md`
- `../decisions/jido_ai.llm_backend_boundary.md`
- `lib/jido_ai.ex`
- `lib/jido_ai/agent.ex`
- `lib/jido_ai/directive/*.ex`
- `lib/jido_ai/runtime/*.ex`
- `lib/jido_ai/turn.ex`
- `lib/mix/tasks/*.ex`
- `deps/jido_harness` or `mix.exs` dependency surface when added

## Relevant Assumptions / Defaults
- Phases 1 through 3 have already introduced a stable backend boundary and normalized runtime or turn inputs enough for a second backend to participate.
- `Jido.Harness` is CLI-agent oriented, so not every current ReqLLM feature is automatically portable; unsupported capability behavior must remain explicit and typed.
- ReqLLM remains the default backend and the source of truth for embeddings, structured object generation, and any message or tool semantics that Harness cannot yet satisfy.
- Harness-specific provider, session, cwd, and attachment semantics must remain additive and must not overload current ReqLLM model-alias contracts.

[ ] 4 Phase 4 - Harness Adapter and Capability-Gated Adoption
  Add the first `Jido.Harness` backend adapter, translate its CLI-oriented runtime into canonical Jido.AI contracts, and expose bounded additive adoption without breaking ReqLLM-default behavior.

  [ ] 4.1 Section - Harness Backend Adapter Implementation
    Build the adapter that turns backend-neutral Jido.AI requests into Harness run requests and converts Harness events back into canonical runtime and turn inputs.

    [ ] 4.1.1 Task - Implement the Harness request adapter
      Add the translation path from canonical Jido.AI backend requests into `Jido.Harness.RunRequest` and explicit provider execution.

      [ ] 4.1.1.1 Subtask - Map prompt, optional model, timeout, system prompt, workspace path, attachments, allowed tools, and metadata into Harness request fields without changing the Jido.AI public API surface.
      [ ] 4.1.1.2 Subtask - Add explicit additive backend and provider configuration for Harness-backed execution rather than overloading current model aliases.
      [ ] 4.1.1.3 Subtask - Keep request validation and user-facing failure shaping bounded and typed when Harness prerequisites or adapter lookup fail.

    [ ] 4.1.2 Task - Implement the Harness event adapter
      Convert `Jido.Harness.Event` streams into canonical Jido.AI runtime events and normalized turn inputs instead of letting CLI-agent raw event shapes leak upward.

      [ ] 4.1.2.1 Subtask - Map Harness progress, completion, usage, session, and failure events into the existing Jido.AI runtime event vocabulary.
      [ ] 4.1.2.2 Subtask - Preserve session identifiers, timestamps, and provider metadata where they fit the canonical runtime metadata contract.
      [ ] 4.1.2.3 Subtask - Define canonical translation for final answer or tool-related outcomes so turn shaping and request completion remain explicit.

  [ ] 4.2 Section - Capability-Gated Public Adoption
    Expose Harness-backed behavior only where the backend can satisfy the stable contract, and fail explicitly where it cannot.

    [ ] 4.2.1 Task - Adopt Harness for compatible request-bearing surfaces
      Enable Harness-backed execution on bounded public paths where prompt plus workspace semantics are a natural fit and the backend contract can be satisfied cleanly.

      [ ] 4.2.1.1 Subtask - Define which existing public facades, agent request flows, or runtime paths are eligible for Harness-backed execution in the first adoption slice.
      [ ] 4.2.1.2 Subtask - Preserve ReqLLM as the default path for ineligible or unsupported surfaces instead of broadening Harness usage implicitly.
      [ ] 4.2.1.3 Subtask - Keep additive backend selection explicit in config and request-scoped overrides so callers never switch execution models accidentally.

    [ ] 4.2.2 Task - Make unsupported capability gaps explicit
      Keep the package honest by failing clearly when Harness cannot satisfy an existing stable Jido.AI surface such as embeddings, structured objects, or local tool loops.

      [ ] 4.2.2.1 Subtask - Return typed unsupported-capability outcomes for embeddings, structured object generation, and other ReqLLM-only surfaces when Harness is selected.
      [ ] 4.2.2.2 Subtask - Return typed unsupported outcomes for unsupported tool or message-history semantics rather than silently flattening behavior.
      [ ] 4.2.2.3 Subtask - Document and expose the effective backend capability matrix in contributor-facing and user-facing configuration guidance.

  [ ] 4.3 Section - Phase 4 Integration Tests
    Verify the Harness adapter can run bounded compatible requests through canonical Jido.AI runtime contracts and that unsupported capability gaps remain explicit and non-breaking.

    [ ] 4.3.1 Task - Harness adapter runtime scenarios
      Prove Harness-backed execution can enter and leave the Jido.AI runtime through the canonical request and event model without leaking CLI-agent internals.

      [ ] 4.3.1.1 Subtask - Add coverage proving a Harness-backed request is translated into `Jido.Harness.RunRequest` with the expected prompt, cwd, timeout, and metadata shaping.
      [ ] 4.3.1.2 Subtask - Add coverage proving Harness event streams are translated into canonical Jido.AI runtime events and request completion behavior.
      [ ] 4.3.1.3 Subtask - Add coverage proving cancellation and degraded runtime failures remain typed and recoverable through the Jido.AI contract boundary.

    [ ] 4.3.2 Task - Unsupported capability and fallback scenarios
      Prove Harness-backed selection does not silently degrade stable Jido.AI surfaces that the backend cannot satisfy.

      [ ] 4.3.2.1 Subtask - Add coverage proving embeddings and structured object generation fail with typed unsupported-capability outcomes when Harness is selected.
      [ ] 4.3.2.2 Subtask - Add coverage proving unsupported local tool or message-history behavior does not masquerade as successful parity.
      [ ] 4.3.2.3 Subtask - Verify ReqLLM-default behavior and current public API compatibility remain intact after Harness adoption is introduced.
