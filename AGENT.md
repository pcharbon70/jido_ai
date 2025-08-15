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

## SDLC
- **Coverage Goal**: Test coverage goal should be 90%+
- **Code Quality**: Use `mix quality` to run all checks
  - Fix all compiler warnings
  - Fix all dialyzer warnings
  - Add `@type` to all custom types
  - Add `@spec` to all public functions
  - Add `@doc` to all public functions and `@moduledoc` to all modules

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
- **HTTP Testing**: Use Req.Test for HTTP mocking instead of Mimic - provides cleaner stubs and better integration
- **Error Handling**: Return `{:ok, result}` or `{:error, reason}` tuples, use `with` for complex flows
- **Imports**: Group aliases at module top, prefer explicit over wildcard imports
- **Naming**: `snake_case` for functions/variables, `PascalCase` for modules

## Data Architecture

### Core Data Structures

**Provider** (`Jido.AI.Provider`): Represents an AI service provider (OpenAI, Anthropic, etc.)
- `id` (atom): Unique provider identifier  
- `name` (string): Display name
- `base_url` (string): API endpoint URL (centralized here, not in models)
- `env` (list of atoms): Environment variable names for API keys
- `doc` (string): Provider description
- `models` (map): Collection of supported Model structs keyed by model ID

**Model** (`Jido.AI.Model`): Represents a specific AI model with runtime config and metadata
- Runtime fields: `provider` (atom), `model` (string), `temperature`, `max_tokens`, `max_retries`
- Metadata fields: `id`, `name`, `attachment`, `reasoning`, `tool_call`, `cost`, `limit`, `modalities`, etc.
- API access (base_url, api_key) is handled via the Provider, following DRY principles

### Data Pipeline

1. **Source**: Models.dev API (https://models.dev/api.json) - Community registry of AI models
2. **ETL**: `mix jido.ai.model_sync` downloads, transforms, and stores provider data
3. **Storage**: JSON files in `priv/models_dev/{provider}.json` with normalized schema
4. **Runtime**: Provider/Model structs loaded from JSON for application use

### Models.dev Integration

The `mix jido.ai.model_sync` task fetches model metadata from models.dev which provides:
- Model capabilities (tool calling, reasoning, attachments)
- Cost data (input/output pricing, cache costs)
- Technical limits (context length, output tokens)
- Modality support (text, image, audio, video)
- Release and update dates

**Field Mapping**:
- models.dev `providerId` → our `provider` field
- models.dev `providerModelId` → our `provider_model_id` field  
- models.dev cost/limit structures → validated into our typed structs
- We add `base_url` via our provider modules
- Default API keys from the `env` field are added to the `api_key` field, and `Keyring` is used to get the actual key from the environment or Application config
- We filter out models.dev fields like `npm` package info we don't need

**Schema Mismatch Handling**:
- Provider `base_url`: Injected via hardcoded lookup table in model_sync
- Provider `env`: Configured per provider (e.g., `["OPENAI_API_KEY"]`)
- Missing metadata: Sensible defaults applied during Model construction

## Testing Approach
- **HTTP Mocking**: Use `Req.Test.stub/2` for HTTP request mocking
- **Test Configuration**: Configure HTTP options with `[plug: {Req.Test, :test_name}]`
- **Response Helpers**: Use `Req.Test.json/2`, `Req.Test.transport_error/2` for clean responses
- **Verification**: Use `Req.Test.verify!/1` to ensure all stubs are called
