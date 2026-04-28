# Phase 5 - Strategy, Plugin, and Rollout Convergence

<!-- covers: package.jido_ai.spec_led_workspace -->

Back to index: [README](README.md)

## Relevant Shared APIs / Interfaces
- `../specs/strategies_and_reasoning.spec.md`
- `../specs/plugins_and_capabilities.spec.md`
- `../specs/runtime_contracts_and_observability.spec.md`
- `../specs/tooling_and_configuration.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_ai.llm_backend_boundary.md`
- `lib/jido_ai/reasoning/**/*.ex`
- `lib/jido_ai/agents/strategies/*.ex`
- `lib/jido_ai/plugins/**/*.ex`
- `lib/jido_ai/actions/reasoning/run_strategy.ex`
- `README.md`
- `AGENTS.md`
- `guides/`
- `test/`

## Relevant Assumptions / Defaults
- Phases 1 through 4 have already established backend-neutral request and runtime seams, preserved ReqLLM default behavior, and added a bounded Harness adapter.
- Strategy and plugin surfaces must remain stable for callers even when the runtime below them can choose between ReqLLM and Harness execution paths.
- Not every reasoning or plugin capability will be backend-agnostic on day one, so capability gating and explicit unsupported outcomes remain acceptable and preferable to fake parity.
- Final rollout work must leave current-truth docs, specs, and verification paths aligned with the real backend matrix and compatibility guarantees.

[ ] 5 Phase 5 - Strategy, Plugin, and Rollout Convergence
  Adopt the backend boundary across strategies, capability plugins, docs, and verification so dual-backend behavior becomes explicit, testable, and contributor-maintainable without breaking the stable package surface.

  [ ] 5.1 Section - Strategy and Plugin Backend Adoption
    Connect strategy runners and capability plugins to the backend-aware runtime path while keeping their public routes and default ReqLLM behavior stable.

    [ ] 5.1.1 Task - Route strategy runners through backend-aware execution
      Ensure ReAct, CoT, and delegated reasoning strategies rely on the normalized backend/runtime boundary instead of transport-specific assumptions.

      [ ] 5.1.1.1 Subtask - Keep current strategy entrypoints, macros, and request signals stable while the runtime below them becomes backend-aware.
      [ ] 5.1.1.2 Subtask - Preserve ReqLLM parity for strategy paths that already depend on streaming, tool calls, or message-history semantics.
      [ ] 5.1.1.3 Subtask - Gate Harness adoption on strategy capability support instead of implicitly routing all reasoning families to a CLI-agent backend.

    [ ] 5.1.2 Task - Adopt backend-aware behavior in public capability plugins
      Ensure Chat, Planning, and reasoning plugins continue to route through stable public actions while making backend selection and unsupported capability behavior explicit.

      [ ] 5.1.2.1 Subtask - Keep current plugin signal routes and plugin-state defaults stable while their underlying action or runtime execution becomes backend-aware.
      [ ] 5.1.2.2 Subtask - Keep cross-cutting plugins such as ModelRouting, Policy, Retrieval, and Quota backend-agnostic by preserving their bounded request and signal contracts.
      [ ] 5.1.2.3 Subtask - Make plugin-level unsupported capability outcomes explicit where a selected backend cannot satisfy the routed action or reasoning behavior.

  [ ] 5.2 Section - Documentation, Release, and Contributor Convergence
    Finish the migration by aligning docs, configuration reference, and repo-owned verification with the real backend matrix and compatibility guarantees.

    [ ] 5.2.1 Task - Update docs and contributor guidance for backend-aware runtime behavior
      Make the final user-facing and maintainer-facing documentation explicit about backend selection, defaults, compatibility guarantees, and unsupported-capability behavior.

      [ ] 5.2.1.1 Subtask - Update README and user guides to explain ReqLLM-default behavior, additive Harness selection, and the stable public API contract.
      [ ] 5.2.1.2 Subtask - Update configuration and developer guides to document backend selection, capability gating, and normalization boundaries.
      [ ] 5.2.1.3 Subtask - Update AGENTS and usage rules so contributors preserve the API-compatibility guarantee while evolving internal backends.

    [ ] 5.2.2 Task - Converge verification and cleanup around the final backend architecture
      Make the final backend-aware design durable by updating repo-owned quality, spec, and test surfaces to measure what now matters.

      [ ] 5.2.2.1 Subtask - Add durable test groupings or helpers for backend-matrix verification across ReqLLM-default and Harness-enabled scenarios.
      [ ] 5.2.2.2 Subtask - Retire or isolate transport-specific helpers that no longer belong above backend adapters once strategy and plugin adoption is complete.
      [ ] 5.2.2.3 Subtask - Keep specs, ADRs, planning docs, and generated workspace state aligned with the final backend-aware runtime architecture.

  [ ] 5.3 Section - Phase 5 Integration Tests
    Verify strategies, plugins, and repo-owned docs or verification surfaces remain coherent after backend-aware runtime adoption and that public contracts stay stable across the rollout.

    [ ] 5.3.1 Task - Strategy and plugin adoption scenarios
      Prove strategy and plugin surfaces still behave through stable public routes while using the backend-aware runtime under the hood.

      [ ] 5.3.1.1 Subtask - Add coverage proving ReAct and delegated reasoning runners preserve current request and event behavior on the ReqLLM path after backend adoption.
      [ ] 5.3.1.2 Subtask - Add coverage proving compatible plugin routes can opt into backend-aware execution without changing their public signal contracts.
      [ ] 5.3.1.3 Subtask - Add coverage proving unsupported backend selections for strategy or plugin behavior fail explicitly with typed outcomes.

    [ ] 5.3.2 Task - Rollout convergence scenarios
      Prove the final backend-aware architecture is documented, verifiable, and non-breaking for contributors and existing callers.

      [ ] 5.3.2.1 Subtask - Add coverage proving current docs and configuration reference describe the final backend matrix and compatibility guarantees accurately.
      [ ] 5.3.2.2 Subtask - Add coverage proving the repo-owned verification path can exercise both ReqLLM-default and Harness-enabled scenarios where supported.
      [ ] 5.3.2.3 Subtask - Verify the spec workspace, ADRs, and planning index remain coherent after the full backend-aware rollout plan is in place.
