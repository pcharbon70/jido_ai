# Phase 3 - Runtime, Turn, and Tooling Normalization

<!-- covers: package.jido_ai.spec_led_workspace -->

Back to index: [README](README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_contracts_and_observability.spec.md`
- `../specs/thread_context_projection.spec.md`
- `../specs/actions_and_tool_calling.spec.md`
- `../specs/strategies_and_reasoning.spec.md`
- `../decisions/jido_ai.llm_backend_boundary.md`
- `lib/jido_ai/directive/*.ex`
- `lib/jido_ai/directive/helpers.ex`
- `lib/jido_ai/runtime/*.ex`
- `lib/jido_ai/signals/*.ex`
- `lib/jido_ai/turn.ex`
- `lib/jido_ai/tool_adapter.ex`
- `lib/jido_ai/reasoning/react/config.ex`
- `lib/jido_ai/reasoning/react/runner.ex`

## Relevant Assumptions / Defaults
- Phase 2 has already routed direct facades and standalone actions through the ReqLLM backend adapter.
- The current runtime, directives, turn shaping, and tool loop still carry ReqLLM-specific assumptions that must be normalized before a second backend can participate cleanly.
- Canonical signal namespaces, runtime event kinds, and request or cancellation semantics must remain stable while internal event translation changes.
- Local Jido tool execution remains a first-class contract and should only be widened to alternate backends through explicit capability and manifest work.

[ ] 3 Phase 3 - Runtime, Turn, and Tooling Normalization
  Refactor runtime directives, turn shaping, and tool manifests so backend-specific provider or CLI semantics are normalized before they influence strategy code or public runtime consumers.

  [ ] 3.1 Section - Directive and Runtime Execution Normalization
    Move directive runtime behavior from transport-specific calls toward backend-neutral execution requests while preserving current signals and runtime events.

    [ ] 3.1.1 Task - Route LLM directives through the backend boundary
      Cut `LLMGenerate`, `LLMStream`, and adjacent runtime execution paths over to backend-neutral execution instead of direct ReqLLM transport calls.

      [ ] 3.1.1.1 Subtask - Make directive helpers assemble backend-neutral requests rather than transport-specific option sets at the public runtime layer.
      [ ] 3.1.1.2 Subtask - Keep canonical `ai.llm.*`, `ai.tool.*`, and request lifecycle signals stable while backend-specific outcomes are translated underneath them.
      [ ] 3.1.1.3 Subtask - Preserve cancellation, timeout, and correlation metadata semantics as the runtime crosses into the backend boundary.

    [ ] 3.1.2 Task - Normalize runtime event translation
      Ensure backend-specific event or streaming shapes are converted into canonical Jido.AI runtime events before strategy or product logic consumes them.

      [ ] 3.1.2.1 Subtask - Define one translation path from backend-neutral stream events into canonical runtime event kinds such as `:llm_started`, `:llm_delta`, and `:llm_completed`.
      [ ] 3.1.2.2 Subtask - Keep telemetry metadata and measurements canonical even when different backends emit different raw progress signals.
      [ ] 3.1.2.3 Subtask - Ensure degraded, unsupported, and backend-failed outcomes stay typed and recoverable through the canonical runtime event model.

  [ ] 3.2 Section - Turn and Tool Manifest Normalization
    Remove the remaining hard dependency on ReqLLM response and tool structs from the canonical turn and runtime-tooling boundaries.

    [ ] 3.2.1 Task - Widen `Jido.AI.Turn` to backend-neutral normalized inputs
      Make turn shaping depend on normalized result maps and canonical tool-call records rather than requiring ReqLLM-specific response structs.

      [ ] 3.2.1.1 Subtask - Preserve current ReqLLM response support while adding explicit normalized backend-result input paths.
      [ ] 3.2.1.2 Subtask - Keep assistant-message, tool-message, and usage normalization behavior stable for the ReqLLM path while widening the accepted upstream input shape.
      [ ] 3.2.1.3 Subtask - Keep `Turn.extract_text`, `Turn.needs_tools?`, and tool-result attachment semantics stable across normalized backend inputs.

    [ ] 3.2.2 Task - Introduce backend-neutral tool manifests above transport adapters
      Separate the internal Jido tool contract from ReqLLM transport structs so different backends can advertise or reject tool support explicitly.

      [ ] 3.2.2.1 Subtask - Define a canonical internal tool manifest derived from `Jido.Action` schemas and metadata.
      [ ] 3.2.2.2 Subtask - Keep ReqLLM transport conversion inside its backend adapter instead of the runtime or strategy layer.
      [ ] 3.2.2.3 Subtask - Define how a backend that cannot support local tool calling returns a typed unsupported-capability outcome instead of pretending tools are available.

  [ ] 3.3 Section - Phase 3 Integration Tests
    Verify the runtime and turn layers now consume normalized backend inputs while preserving canonical signals, runtime events, and local tool-loop behavior for the ReqLLM path.

    [ ] 3.3.1 Task - Directive and runtime normalization scenarios
      Prove directives and runtime streams now pass through the backend boundary without changing the canonical external runtime contract.

      [ ] 3.3.1.1 Subtask - Add coverage proving `LLMGenerate` and `LLMStream` translate backend results into the same canonical signals and runtime events expected today.
      [ ] 3.3.1.2 Subtask - Add coverage proving timeout, cancellation, and correlation metadata survive backend translation unchanged at the runtime contract boundary.
      [ ] 3.3.1.3 Subtask - Add coverage proving backend failures and unsupported capabilities remain typed and bounded through the canonical runtime event path.

    [ ] 3.3.2 Task - Turn and tool normalization scenarios
      Prove the canonical turn and tool loop can accept normalized backend input while preserving ReqLLM parity and explicit unsupported behavior.

      [ ] 3.3.2.1 Subtask - Add coverage proving `Turn.from_response` and related helpers accept canonical normalized backend result maps alongside current ReqLLM inputs.
      [ ] 3.3.2.2 Subtask - Add coverage proving ReqLLM-backed tool loops still project assistant and tool follow-up messages unchanged.
      [ ] 3.3.2.3 Subtask - Add coverage proving non-tool-capable backends fail with typed unsupported outcomes instead of silent no-op tool behavior.
