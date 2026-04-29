# Plugins And Capabilities

Current-truth contract for public capability plugins, default plugin composition, and cross-cutting runtime controls.

```spec-meta
id: jido_ai.plugins
kind: feature
status: active
summary: Public capability plugins package chat, planning, and strategy invocation while cross-cutting plugins handle routing, policy, retrieval, quota, and internal task-supervisor support without changing the stable signal surface as backend selection becomes additive.
surface:
  - lib/jido_ai/plugin_stack.ex
  - lib/jido_ai/plugins/**/*.ex
  - lib/jido_ai/quota/store.ex
  - lib/jido_ai/retrieval/store.ex
  - guides/user/model_routing_and_policy.md
  - guides/user/retrieval_and_quota.md
  - guides/user/migration_plugins_and_signals_v3.md
  - guides/developer/plugins_and_actions_composition.md
  - guides/user/package_overview.md
```

## Requirements

```spec-requirements
- id: jido_ai.plugins.public_plugin_surface
  statement: The public plugin surface shall center on Chat, Planning, and per-strategy reasoning plugins, while TaskSupervisor remains internal runtime infrastructure rather than a public capability recommendation and plugin-level backend/workspace defaults remain additive instead of renaming routes or result contracts.
  priority: must
  stability: stable

- id: jido_ai.plugins.default_plugin_composition
  statement: Default Jido.AI agent composition shall include TaskSupervisor, Policy, and ModelRouting, with Retrieval and Quota enabled explicitly through plugin-stack options.
  priority: must
  stability: stable

- id: jido_ai.plugins.cross_cutting_runtime_plugins
  statement: Model routing, policy, retrieval, and quota plugins shall provide deterministic cross-cutting runtime behavior through stable signal-route and plugin-state contracts.
  priority: must
  stability: stable

- id: jido_ai.plugins.capability_gated_backend_adoption
  statement: Capability plugins shall keep stable signal routes while surfacing backend selection explicitly, allowing compatible plain-text flows to use alternate backends and forcing strategy or tool-heavy routes to fail with typed unsupported outcomes until their runtime contract is normalized.
  priority: must
  stability: evolving

- id: jido_ai.plugins.v3_migration_surface
  statement: The current plugin and signal surface shall keep the v3 migration contract explicit for users upgrading from the removed v2 public plugins.
  priority: should
  stability: evolving
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/plugins_and_actions_composition.md
  covers:
    - jido_ai.plugins.public_plugin_surface
    - jido_ai.plugins.default_plugin_composition

- kind: source_file
  target: lib/jido_ai/plugins/chat.ex
  covers:
    - jido_ai.plugins.public_plugin_surface
    - jido_ai.plugins.capability_gated_backend_adoption

- kind: guide_file
  target: guides/user/model_routing_and_policy.md
  covers:
    - jido_ai.plugins.cross_cutting_runtime_plugins

- kind: guide_file
  target: guides/user/retrieval_and_quota.md
  covers:
    - jido_ai.plugins.cross_cutting_runtime_plugins

- kind: guide_file
  target: guides/user/migration_plugins_and_signals_v3.md
  covers:
    - jido_ai.plugins.v3_migration_surface
```
