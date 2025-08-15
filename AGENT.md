# AGENT.md - Jido AI Development Guide

## Commands
- **Test**: `mix test` (all), `mix test test/path/to/specific_test.exs` (single file), `mix test --trace` (verbose)
- **Lint**: `mix credo` (basic), `mix credo --strict` (strict mode)
- **Format**: `mix format` (format code), `mix format --check-formatted` (verify formatting)
- **Quality**: `mix quality` or `mix q` (runs format, compile, dialyzer, credo, doctor, docs)
- **Compile**: `mix compile` (basic), `mix compile --warnings-as-errors` (strict)
- **Type Check**: `mix dialyzer --format dialyxir`
- **Coverage**: `mix test --cover` (basic), `mix coveralls.html` (HTML report)
- **Docs**: `mix docs` (generate documentation)

## Architecture
Jido AI is an Elixir library for AI agent workflows with multiple LLM providers:
- **Core**: [`lib/jido_ai.ex`](lib/jido_ai.ex) - Main API facade with unified config access via `Jido.AI.config/2`
- **Keyring**: [`lib/jido_ai/keyring.ex`](lib/jido_ai/keyring.ex) - API key management (GenServer)
- **Providers**: [`lib/jido_ai/provider/`](lib/jido_ai/provider/) - LLM provider implementations (OpenAI, Anthropic, etc.)
- **Models**: [`lib/jido_ai/model.ex`](lib/jido_ai/model.ex) - Model configuration and validation

## Public API Overview
The main `Jido.AI` module provides a clean, minimal interface:

### Configuration & Provider Access
- `Jido.AI.config(keyspace, default)` - Get config values using atom list paths with Keyring fallback
- `Jido.AI.api_key(provider)` - Get API key for a provider
- `Jido.AI.list_keys()` - List all configuration keys

### Model & Text Generation
_API is modeled after the Vercel AI SDK_
- `Jido.AI.model(spec)` - Create model from flexible spec (string/tuple/struct)
- `Jido.AI.provider(provider)` - Get provider module from registry 
- `Jido.AI.generate_text(model_spec, prompt, opts)` - Generate text with any model spec
- `Jido.AI.stream_text(model_spec, prompt, opts)` - Stream text generation

## Code Style
- **Formatting**: Uses [`mix format`](.formatter.exs), line length max 120 chars
- **Types**: Add `@spec` to all public functions, use `@type` for custom types
- **Docs**: `@moduledoc` for modules, `@doc` for public functions with examples
- **Testing**: Mirror lib structure in test/, use ExUnit with async when possible, tag slow/integration tests
- **Error Handling**: Return `{:ok, result}` or `{:error, reason}` tuples, use `with` for complex flows
- **Imports**: Group aliases at module top, prefer explicit over wildcard imports
- **Naming**: `snake_case` for functions/variables, `PascalCase` for modules
