# Tooling And Configuration

Current-truth contract for explicit configuration defaults, CLI workflows, and install-time setup helpers.

```spec-meta
id: jido_ai.tooling_and_configuration
kind: workflow
status: active
summary: Repo-owned tooling keeps configuration defaults explicit, exposes shell-first CLI workflows, and provides an Igniter-based install path when available.
surface:
  - config/
  - lib/jido_ai/cli/*.ex
  - lib/mix/tasks/*.ex
  - guides/developer/configuration_reference.md
  - guides/user/cli_workflows.md
```

## Requirements

```spec-requirements
- id: jido_ai.tooling_and_configuration.explicit_configuration_defaults
  statement: Configuration documentation shall keep additive backend selection, model aliases, llm defaults, strategy defaults, plugin defaults, request defaults, security defaults, and CLI defaults explicit instead of implicit runtime convention, including which surfaces remain ReqLLM-only, which request-bearing paths can adopt Harness explicitly, and which strategy/plugin routes stay capability-gated.
  priority: must
  stability: stable

- id: jido_ai.tooling_and_configuration.mix_jido_ai_cli
  statement: mix jido_ai shall support one-shot, stdin, existing-agent, and strategy-adapter workflows with explicit output-format, timeout, and trace behavior.
  priority: must
  stability: stable

- id: jido_ai.tooling_and_configuration.igniter_install_surface
  statement: mix jido_ai.install shall integrate with Igniter when available to seed base configuration and otherwise fail clearly with install guidance.
  priority: should
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/configuration_reference.md
  covers:
    - jido_ai.tooling_and_configuration.explicit_configuration_defaults

- kind: guide_file
  target: guides/user/cli_workflows.md
  covers:
    - jido_ai.tooling_and_configuration.mix_jido_ai_cli

- kind: source_file
  target: lib/mix/tasks/jido_ai.install.ex
  covers:
    - jido_ai.tooling_and_configuration.igniter_install_surface
```
