# Security And Error Model

Current-truth contract for validation, sanitization, redaction, structured AI errors, and recovery boundaries.

```spec-meta
id: jido_ai.security_and_errors
kind: policy
status: active
summary: Validation, sanitization, telemetry redaction, and structured AI error handling provide defense-in-depth across user input, runtime failures, and recovery decisions.
surface:
  - lib/jido_ai/validation.ex
  - lib/jido_ai/error.ex
  - lib/jido_ai/error/*.ex
  - guides/developer/security_and_validation.md
  - guides/developer/error_model_and_recovery.md
```

## Requirements

```spec-requirements
- id: jido_ai.security_and_errors.validation_and_sanitization
  statement: Validation and sanitization surfaces shall enforce bounded prompts, turns, callbacks, and telemetry redaction before untrusted input reaches runtime or user-visible channels.
  priority: must
  stability: stable

- id: jido_ai.security_and_errors.structured_error_taxonomy
  statement: Jido.AI shall keep an AI-specific structured error taxonomy and recovery model across provider, validation, tool, backend capability, and unknown failure classes.
  priority: must
  stability: stable

- id: jido_ai.security_and_errors.sanitized_user_error_boundary
  statement: User-facing error output shall remain sanitized while richer detail stays available for logs, telemetry, and runtime debugging.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/developer/security_and_validation.md
  covers:
    - jido_ai.security_and_errors.validation_and_sanitization

- kind: guide_file
  target: guides/developer/error_model_and_recovery.md
  covers:
    - jido_ai.security_and_errors.structured_error_taxonomy
    - jido_ai.security_and_errors.sanitized_user_error_boundary

- kind: source_file
  target: lib/jido_ai/error.ex
  covers:
    - jido_ai.security_and_errors.structured_error_taxonomy
```
