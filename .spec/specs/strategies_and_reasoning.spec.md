# Strategies And Reasoning

Current-truth contract for built-in reasoning families, explicit strategy selection, and standalone ReAct runtime behavior.

```spec-meta
id: jido_ai.strategies
kind: feature
status: active
summary: Jido.AI ships multiple reasoning strategy families, convenience agent macros, standalone ReAct runtime, and explicit strategy internals instead of prompt-only orchestration.
surface:
  - lib/jido_ai/reasoning/**/*.ex
  - lib/jido_ai/agents/strategies/*.ex
  - guides/user/strategy_selection_playbook.md
  - guides/user/strategy_recipes.md
  - guides/user/standalone_react_runtime.md
  - guides/developer/strategy_internals.md
```

## Requirements

```spec-requirements
- id: jido_ai.strategies.built_in_strategy_families
  statement: Jido.AI shall provide built-in ReAct, CoD, CoT, AoT, ToT, GoT, TRM, and Adaptive reasoning families through convenience agent macros and strategy modules.
  priority: must
  stability: stable

- id: jido_ai.strategies.explicit_strategy_selection
  statement: Strategy choice shall be an explicit workload-level decision with documented defaults, recipes, and tradeoffs rather than an implicit prompt tweak.
  priority: must
  stability: stable

- id: jido_ai.strategies.strategy_internal_contracts
  statement: Strategy implementations shall keep orchestration, machine, worker, and result-shape contracts explicit so strategy-specific behavior stays separate from app-level action APIs.
  priority: must
  stability: evolving

- id: jido_ai.strategies.standalone_react_runtime
  statement: Jido.AI.Reasoning.ReAct shall remain a standalone streaming and checkpoint-aware runtime that can run, start, continue, collect, cancel, steer, and inject outside agent macros.
  priority: should
  stability: evolving
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/user/strategy_selection_playbook.md
  covers:
    - jido_ai.strategies.built_in_strategy_families

- kind: guide_file
  target: guides/user/strategy_recipes.md
  covers:
    - jido_ai.strategies.explicit_strategy_selection

- kind: guide_file
  target: guides/developer/strategy_internals.md
  covers:
    - jido_ai.strategies.strategy_internal_contracts

- kind: guide_file
  target: guides/user/standalone_react_runtime.md
  covers:
    - jido_ai.strategies.standalone_react_runtime
```
