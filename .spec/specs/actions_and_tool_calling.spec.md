# Actions And Tool Calling

Current-truth contract for standalone Jido.AI actions, tool execution loops, and direct retrieval/quota primitives.

```spec-meta
id: jido_ai.actions
kind: feature
status: active
summary: Built-in standalone actions cover LLM generation, tool calling, planning, retrieval, quota, and reasoning execution outside long-lived agents.
surface:
  - lib/jido_ai/actions/**/*.ex
  - lib/jido_ai/tool_adapter.ex
  - lib/jido_ai/effects.ex
  - lib/jido_ai/effects/*.ex
  - guides/user/tool_calling_with_actions.md
  - guides/user/retrieval_and_quota.md
  - guides/developer/actions_catalog.md
```

## Requirements

```spec-requirements
- id: jido_ai.actions.standalone_action_surface
  statement: Jido.AI shall provide standalone action modules for LLM generation, tool orchestration, planning, retrieval, quota, and reasoning execution so AI work can run via Jido.Exec without a long-lived agent.
  priority: must
  stability: stable

- id: jido_ai.actions.tool_calling_loop_contract
  statement: Tool-calling actions and turn helpers shall normalize tool schemas, execute registered Jido.Action tools, and project assistant/tool follow-up messages for iterative loops.
  priority: must
  stability: stable

- id: jido_ai.actions.retrieval_and_quota_actions
  statement: Retrieval and quota actions shall expose direct in-process memory and budget primitives that can be used standalone or behind plugins.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/actions_catalog.md
  covers:
    - jido_ai.actions.standalone_action_surface
    - jido_ai.actions.retrieval_and_quota_actions

- kind: guide_file
  target: guides/user/tool_calling_with_actions.md
  covers:
    - jido_ai.actions.tool_calling_loop_contract

- kind: guide_file
  target: guides/user/retrieval_and_quota.md
  covers:
    - jido_ai.actions.retrieval_and_quota_actions
```
