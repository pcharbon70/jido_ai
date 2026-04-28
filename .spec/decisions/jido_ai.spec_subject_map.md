---
id: jido_ai.spec_subject_map
status: accepted
date: 2026-04-28
affects:
  - repo.governance
---

# Jido.AI Spec Subject Map

## Context

`jido_ai` is no longer a single-surface package. The current repo ships:

- long-lived agent macros and request-handle orchestration
- direct LLM facades and standalone actions
- multiple reasoning strategy families and standalone ReAct runtime
- capability plugins plus cross-cutting routing, policy, retrieval, and quota controls
- directive, signal, telemetry, validation, and error contracts
- a skills system, CLI tasks, install tooling, examples, and quality helpers

That surface is too broad to leave captured only in a package-level spec. We
need stable authored subjects that reflect the real user-facing and
maintainer-facing domains in the repository.

## Decision

Jido.AI current truth is organized as a package-level subject plus these stable
domain subjects:

- core runtime and requests
- thread-context projection
- actions and tool calling
- strategies and reasoning
- plugins and capabilities
- runtime contracts and observability
- security, validation, and error model
- skills system
- tooling and configuration
- examples and quality

Each subject should:

- define a stable contract in one `.spec/specs/*.spec.md` file
- claim the relevant source, guide, and support surface for that domain
- prefer file-backed verification against current user/developer guides when the
  contract is documentation-backed
- use source-backed verification for repo-owned implementation-only support
  surfaces where no better authored current-truth guide exists

Cross-cutting changes to this subject map should be captured by updating this
ADR rather than scattering subject-organization rationale across unrelated
specs.

## Consequences

The spec workspace can now describe the actual Jido.AI product/runtime
boundaries instead of a single catch-all package contract.

The tradeoff is that larger cross-domain changes may require coordinated
updates across multiple subject files, and durable reorganizations of the map
should come back through this ADR.
