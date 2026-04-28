# Thread Context Projection

Current-truth contract for canonical thread events, materialized context, and normalized turn projection.

```spec-meta
id: jido_ai.thread_context_projection
kind: contract
status: active
summary: ReAct keeps append-only thread truth, deterministic Jido.AI.Context projection, and canonical Jido.AI.Turn normalization for follow-up execution.
decisions:
  - jido_ai.llm_backend_boundary
surface:
  - lib/jido_ai/context.ex
  - lib/jido_ai/turn.ex
  - guides/user/thread_context_and_message_projection.md
  - guides/user/turn_and_tool_results.md
  - guides/developer/thread_context_projection_model.md
```

## Requirements

```spec-requirements
- id: jido_ai.thread_context_projection.dual_thread_and_context_model
  statement: ReAct shall keep an append-only core thread log and a deterministic materialized Jido.AI.Context projection for LLM-visible conversation state.
  priority: must
  stability: stable

- id: jido_ai.thread_context_projection.context_projection_semantics
  statement: Jido.AI.Context shall support explicit append, import, restore, and projection semantics for user, assistant, and tool messages with optional system prompt handling.
  priority: must
  stability: stable

- id: jido_ai.thread_context_projection.turn_normalization
  statement: Jido.AI.Turn shall normalize provider or backend responses, extracted text, tool calls, usage metadata, and assistant/tool follow-up messages into one canonical turn contract.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/thread_context_projection_model.md
  covers:
    - jido_ai.thread_context_projection.dual_thread_and_context_model

- kind: guide_file
  target: guides/user/thread_context_and_message_projection.md
  covers:
    - jido_ai.thread_context_projection.context_projection_semantics

- kind: guide_file
  target: guides/user/turn_and_tool_results.md
  covers:
    - jido_ai.thread_context_projection.turn_normalization

- kind: source_file
  target: .spec/decisions/jido_ai.llm_backend_boundary.md
  covers:
    - jido_ai.thread_context_projection.turn_normalization
```
