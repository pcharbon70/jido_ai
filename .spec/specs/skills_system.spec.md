# Skills System

Current-truth contract for module-backed and runtime-loaded skills, registry lifecycle, and skill CLI behavior.

```spec-meta
id: jido_ai.skills_system
kind: feature
status: active
summary: The skills system unifies module-defined and SKILL.md-loaded skills behind one manifest/body/actions/plugins API with registry-backed runtime resolution.
surface:
  - lib/jido_ai/skill.ex
  - lib/jido_ai/skill/*.ex
  - guides/developer/skills_system.md
  - examples/lib/skills/*.ex
  - examples/lib/skills_demo_agent.ex
  - examples/scripts/demo/skills_*.exs
```

## Requirements

```spec-requirements
- id: jido_ai.skills_system.unified_skill_abstraction
  statement: The skills system shall support both module-defined skills and runtime-loaded SKILL.md skills through one manifest/body/allowed-tools/actions/plugins abstraction.
  priority: must
  stability: stable

- id: jido_ai.skills_system.registry_lifecycle
  statement: Skill registry behavior shall support explicit startup, lazy ensure_started safety, registration, lookup, unregister, and teardown without fragile startup ordering.
  priority: must
  stability: stable

- id: jido_ai.skills_system.skill_cli_surface
  statement: mix jido_ai.skill shall provide list, show, and validate flows with predictable usage, strict, and json behavior for skill files and directories.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/skills_system.md
  covers:
    - jido_ai.skills_system.unified_skill_abstraction
    - jido_ai.skills_system.registry_lifecycle
    - jido_ai.skills_system.skill_cli_surface
```
