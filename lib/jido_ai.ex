defmodule Jido.AI do
  @moduledoc """
  Jido AI interface with ergonomic APIs for models, providers, and text generation.

  This module provides a simplified facade for common AI operations, including:
  - Provider registry access
  - API key management
  - Model creation and configuration
  - Text generation and streaming

  ## Configuration API

      # Get API keys for different providers
      Jido.AI.api_key(:openai)
      Jido.AI.api_key(:anthropic)

      # Get provider from registry
      {:ok, provider_module} = Jido.AI.provider(:openai)

      # List all configuration keys
      Jido.AI.list_keys()

  ## Model and Text Generation API

      # Create models - multiple formats supported
      {:ok, model} = Jido.AI.model("openrouter:anthropic/claude-3.5-sonnet")
      {:ok, model} = Jido.AI.model({:openai, model: "gpt-4o", temperature: 0.7})
      {:ok, model} = Jido.AI.model({:openrouter, model: "anthropic/claude-3.5-sonnet", max_tokens: 2000})

      # Text generation - flexible model specs
      {:ok, text} = Jido.AI.generate_text("openrouter:anthropic/claude-3.5-sonnet", "Hello!", [])
      {:ok, text} = Jido.AI.generate_text({:openrouter, model: "anthropic/claude-3.5-sonnet"}, "Tell me a joke", [])

      # Text streaming
      {:ok, stream} = Jido.AI.stream_text("openrouter:anthropic/claude-3.5-sonnet", "Hello!", [])

  """

  alias Jido.AI.{Keyring, Model}

  # ===========================================================================
  # Configuration API - Simple facades for common operations
  # ===========================================================================

  @doc """
  Gets a configuration value from the keyring.

  Key lookup is case-insensitive and accepts both atoms and strings.

  ## Parameters

    * `key` - The configuration key (atom or string, case-insensitive)

  ## Examples

      Jido.AI.api_key(:openai_api_key)
      Jido.AI.api_key("ANTHROPIC_API_KEY")
      Jido.AI.api_key("OpenAI_API_Key")

  """
  @spec api_key(atom() | String.t()) :: String.t() | nil
  def api_key(key) when is_atom(key) do
    Keyring.get(Keyring, key, nil)
  end

  def api_key(key) when is_binary(key) do
    normalized = String.downcase(key)
    Keyring.get(normalized, nil)
  end

  @doc """
  Lists all available configuration keys.

  Returns a list of strings representing available configuration keys.
  """
  @spec list_keys() :: [String.t()]
  def list_keys do
    Keyring.list(Keyring)
  end

  @doc """
  Gets configuration values using atom list paths with Keyring fallback.

  Supports various configuration access patterns:
  - Simple keys: `[:http_client]` 
  - Provider configs: `[:openai]` 
  - Nested provider settings: `[:openai, :api_key]`
  - Timeout configs: `[:receive_timeout]`

  ## Examples

      # Get provider config
      Jido.AI.config([:openai])
      
      # Get specific provider setting
      Jido.AI.config([:openai, :base_url])
      
      # Get timeout with default
      Jido.AI.config([:receive_timeout], 60_000)
      
      # Get API key with Keyring fallback
      Jido.AI.config([:openai, :api_key])
  """
  @spec config(list(atom()), term()) :: term()
  def config(keyspace, default \\ nil)

  def config([main_key | rest] = keyspace, default) when is_list(keyspace) do
    case Application.get_env(:jido_ai, main_key) do
      nil when rest == [] ->
        # For simple keys like [:http_client], try keyring fallback
        Keyring.get(Keyring, main_key, default)

      nil ->
        # For nested keys like [:openai, :api_key], check keyring with provider format
        if length(rest) == 1 and hd(rest) == :api_key do
          key = :"#{main_key}_api_key"
          Keyring.get(Keyring, key, default)
        else
          default
        end

      main when rest == [] ->
        main

      main when is_list(main) ->
        Enum.reduce(rest, main, fn next_key, current ->
          case Keyword.fetch(current, next_key) do
            {:ok, val} ->
              val

            :error ->
              # For :api_key, try keyring fallback with provider format
              if next_key == :api_key do
                key = :"#{main_key}_api_key"
                Keyring.get(Keyring, key, default)
              else
                default
              end
          end
        end)

      _main ->
        default
    end
  end

  # ===========================================================================
  # Model API - Developer sugar for creating models
  # ===========================================================================

  @doc """
  Gets a provider module from the provider registry.

  ## Parameters

    * `provider` - The AI provider atom

  ## Examples

      {:ok, provider_module} = Jido.AI.provider(:openai)
      {:ok, provider_module} = Jido.AI.provider(:anthropic)
      {:error, "Provider not found: unknown"} = Jido.AI.provider(:unknown)

  """
  @spec provider(atom()) :: {:ok, module()} | {:error, String.t()}
  def provider(provider) do
    Jido.AI.Provider.Registry.fetch(provider)
  end

  @doc """
  Creates a model from various input formats for maximum developer ergonomics.

  Supports multiple input formats:
  - String format: `"provider:model"` (e.g., "openrouter:anthropic/claude-3.5-sonnet")
  - Tuple format: `{provider, opts}` where provider is atom and opts is keyword list
  - Existing Model struct (returns as-is)

  ## Examples

      # String format - super concise
      Jido.AI.model("openrouter:anthropic/claude-3.5-sonnet")

      # Tuple format - flexible with options
      Jido.AI.model({:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7})

      # With additional configuration
      Jido.AI.model({:openai, model: "gpt-4", max_tokens: 2000, temperature: 0.5})

  """
  @spec model(Model.t() | {atom(), keyword()} | String.t()) ::
          {:ok, Model.t()} | {:error, String.t()}
  def model(spec) do
    Model.from(spec)
  end

  @doc """
  Generates text using an AI model with maximum developer ergonomics.

  Accepts flexible model specifications and generates text using the appropriate provider.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - Model struct: `%Jido.AI.Model{}`
      - String format: `"openrouter:anthropic/claude-3.5-sonnet"`
      - Tuple format: `{:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7}`
    * `prompt` - Text prompt to generate from (string)
    * `opts` - Additional options (keyword list)

  ## Examples

      # String format - super concise
      {:ok, response} = Jido.AI.generate_text(
        "openrouter:anthropic/claude-3.5-sonnet",
        "Hello, world!",
        []
      )

      # Tuple format with model-specific options
      {:ok, response} = Jido.AI.generate_text(
        {:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7},
        "Tell me a joke",
        []
      )

      # With additional generation options
      {:ok, response} = Jido.AI.generate_text(
        {:openrouter, model: "anthropic/claude-3.5-sonnet"},
        "Write a haiku",
        max_tokens: 100
      )

  """
  @spec generate_text(Model.t() | {atom(), keyword()} | String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_text(model_spec, prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    with {:ok, model} <- ensure_model_struct(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      provider_module.generate_text(model, prompt, opts)
    end
  end

  @doc """
  Streams text using an AI model with maximum developer ergonomics.

  Accepts flexible model specifications and streams text using the appropriate provider.
  Returns a Stream that emits text chunks as they arrive.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - Model struct: `%Jido.AI.Model{}`
      - String format: `"openrouter:anthropic/claude-3.5-sonnet"`
      - Tuple format: `{:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7}`
    * `prompt` - Text prompt to generate from (string)
    * `opts` - Additional options (keyword list)

  ## Examples

      # String format - super concise
      {:ok, stream} = Jido.AI.stream_text(
        "openrouter:anthropic/claude-3.5-sonnet",
        "Hello, world!",
        []
      )

      # Consume the stream
      stream |> Enum.each(&IO.write/1)

      # Tuple format with model-specific options
      {:ok, stream} = Jido.AI.stream_text(
        {:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7},
        "Tell me a joke",
        []
      )

  """
  @spec stream_text(Model.t() | {atom(), keyword()} | String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_text(model_spec, prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    with {:ok, model} <- ensure_model_struct(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      provider_module.stream_text(model, prompt, opts)
    end
  end

  @doc false
  @spec ensure_model_struct(Model.t() | {atom(), keyword()} | String.t()) ::
          {:ok, Model.t()} | {:error, String.t()}
  defp ensure_model_struct(%Model{} = model), do: {:ok, model}
  defp ensure_model_struct(model_spec), do: model(model_spec)
end
