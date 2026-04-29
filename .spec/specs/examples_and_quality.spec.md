# Examples And Quality

Current-truth contract for top-level runnable examples and repo-owned quality checkpoint helpers.

```spec-meta
id: jido_ai.examples_and_quality
kind: workflow
status: active
summary: Example agents and demo scripts stay outside the core compile path, while repo-owned quality helpers define repeatable gate and traceability checks.
surface:
  - examples/
  - lib/jido_ai/quality/checkpoint.ex
  - test/**/*.exs
  - test/support/*.ex
```

## Requirements

```spec-requirements
- id: jido_ai.examples_and_quality.top_level_runnable_examples
  statement: Runnable agents, tools, skills, and demo scripts shall live in the top-level examples/ tree and stay out of the core package compile path by default.
  priority: must
  stability: stable

- id: jido_ai.examples_and_quality.quality_checkpoint_helpers
  statement: Repo-owned quality checkpoint helpers shall define canonical fast/full gate command sets and traceability closure utilities for release hygiene.
  priority: should
  stability: evolving

- id: jido_ai.examples_and_quality.executable_contract_regression_tests
  statement: Repo-owned tests shall capture executable regression coverage for current-truth contracts as new internal seams or error boundaries are introduced.
  priority: should
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: examples/README.md
  covers:
    - jido_ai.examples_and_quality.top_level_runnable_examples

- kind: source_file
  target: lib/jido_ai/quality/checkpoint.ex
  covers:
    - jido_ai.examples_and_quality.quality_checkpoint_helpers

- kind: source_file
  target: test/jido_ai/backend_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/error/model_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/backends_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/backends/req_llm_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/directive/exec_runtime_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/react/runtime_runner_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/integration/backend_boundary_phase1_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests

- kind: source_file
  target: test/jido_ai/integration/backend_boundary_phase2_test.exs
  covers:
    - jido_ai.examples_and_quality.executable_contract_regression_tests
```
