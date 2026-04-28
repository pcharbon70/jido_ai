# Package

High-level package contract for Jido.AI.

```spec-meta
id: package.jido_ai
kind: package
status: active
summary: jido_ai is the Jido ecosystem AI runtime layer for tool-using agents, reusable actions, direct LLM facade calls, and explicit reasoning strategy execution through stable public APIs with explicit LLM backend boundaries.
decisions:
  - jido_ai.spec_subject_map
  - jido_ai.llm_backend_boundary
surface:
  - AGENTS.md
  - CHANGELOG.md
  - CONTRIBUTING.md
  - LICENSE.md
  - mix.exs
  - README.md
  - usage-rules.md
  - .spec/README.md
  - .spec/AGENTS.md
  - .spec/specs/*.spec.md
  - .spec/decisions/*.md
  - .spec/planning/*.md
```

## Requirements

```spec-requirements
- id: package.jido_ai.runtime_layer
  statement: jido_ai shall provide the AI runtime layer for Jido for defining tools and agents and for running synchronous or asynchronous requests with request orchestration and observability.
  priority: must
  stability: stable

- id: package.jido_ai.agent_and_action_surfaces
  statement: jido_ai shall expose both long-lived agent surfaces and reusable action or runtime surfaces so AI behavior can run inside Jido agents or inside direct workflow execution paths.
  priority: must
  stability: stable

- id: package.jido_ai.explicit_policy_boundaries
  statement: jido_ai shall keep model routing, timeout, retry, structured I/O, and tool policy explicit while keeping provider-specific or CLI-runtime-specific behavior behind explicit LLM backend integration boundaries.
  priority: must
  stability: stable

- id: package.jido_ai.public_api_surface_compatibility
  statement: Cross-cutting LLM backend evolution shall preserve the previous-version public API surface, including stable entrypoint names, arities, return-shape contracts, and canonical signal/event contracts.
  priority: must
  stability: stable

- id: package.jido_ai.spec_led_workspace
  statement: The repository shall maintain a package-local .spec workspace for current-truth specs, durable ADRs, phased implementation planning, and generated spec state aligned with code, guides, and tests.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: readme_file
  target: README.md
  covers:
    - package.jido_ai.runtime_layer
    - package.jido_ai.agent_and_action_surfaces

- kind: contract
  target: usage-rules.md
  covers:
    - package.jido_ai.explicit_policy_boundaries
    - package.jido_ai.public_api_surface_compatibility

- kind: source_file
  target: .spec/decisions/jido_ai.llm_backend_boundary.md
  covers:
    - package.jido_ai.explicit_policy_boundaries
    - package.jido_ai.public_api_surface_compatibility

- kind: source_file
  target: AGENTS.md
  covers:
    - package.jido_ai.spec_led_workspace

- kind: source_file
  target: .spec/README.md
  covers:
    - package.jido_ai.spec_led_workspace

- kind: source_file
  target: .spec/planning/README.md
  covers:
    - package.jido_ai.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-01-backend-boundary-and-compatibility-foundation.md
  covers:
    - package.jido_ai.spec_led_workspace
```
