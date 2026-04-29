# AGENTS.md - Jido.AI Guide

## Intent
Build tool-using AI agents with explicit strategy, runtime policy, and reliable request orchestration.

## Runtime Baseline
- Elixir `~> 1.18`
- OTP `27+` (release QA baseline)

## Commands
- `mix test` (default alias excludes `:flaky`)
- `mix test.fast` (stable smoke suite)
- `mix precommit` (`format`, `compile --warnings-as-errors`, `doctor --summary --raise`, `test.fast`)
- `mix q` or `mix quality` (`format`, `compile`, `credo`, `doctor`, `dialyzer`)
- `mix docs`

## Architecture Snapshot
- `Jido.AI.Agent` + strategy agents (`CoD`, `CoT`, `AoT`, `ToT`, `GoT`, `TRM`, `Adaptive`)
- `Jido.AI.Actions.*`: reusable runtime actions for chat/tool/structured flows
- ReqLLM-backed provider/model integration today, with backend abstraction preserved at runtime boundaries
- Policy/observability modules for retries, quotas, telemetry, and traceability

## Standards
- Keep model selection, timeout, retry, and tool policy explicit
- Use **Zoi-first** schemas for tool inputs and structured outputs
- Keep provider-specific or CLI-runtime-specific behavior behind explicit LLM backend integration boundaries
- Keep backend selection additive through `backend`, `workspace`, and `backend_metadata`; do not overload `model_aliases` to express transport/runtime choices
- Preserve the current public API surface while evolving internal LLM backends
- Keep ReqLLM as the default for strategy runners and any capability that still depends on structured output, embeddings, or local Jido tool-loop semantics until the runtime contract changes explicitly
- Preserve tagged tuple and structured error contracts
- Prefer deterministic fallback behavior over ad-hoc prompt pipelines

## Spec Led Development

<!-- covers: package.jido_ai.spec_led_workspace -->

`.spec/` is the package-local Spec Led Development workspace for current-truth specs and durable ADRs.

- Run `mix spec.prime --base HEAD` when entering the repo or handing work to another agent
- Keep `.spec/specs/*.spec.md` aligned with code, guides, and tests when behavior changes
- Use `.spec/decisions/*.md` only for durable cross-cutting ADRs
- Run `mix spec.next` after code, docs, or tests change, then `mix spec.check --base ...` when work is ready to finish
- If spec tooling is blocked by an unrelated compile or runtime issue, report the blocker instead of inventing a passing result

## Testing and QA
- Cover strategy behavior, tool-call loops, and error/fallback handling
- Keep flaky tests isolated behind tags; maintain a stable smoke subset (`mix test.fast`)
- Validate public examples/scripts when runtime behavior changes

## Release Hygiene
- Keep semver ranges stable (`~> 2.0` ecosystem peers; package currently `2.0.0-rc.0`)
- Use Conventional Commits
- Do not update `CHANGELOG.md` unless the user explicitly requests it
- Update guides and migration notes for behavior/API changes

## References
- `README.md`
- `.spec/README.md`
- `usage-rules.md`
- `guides/`
- https://hexdocs.pm/jido_ai
