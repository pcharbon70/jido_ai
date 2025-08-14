defmodule Jido.AI do
  @moduledoc """
  High-level AI interface with ergonomic APIs for chat, models, and configuration.

  This module provides a simplified facade for common AI operations, including:
  - Provider configuration and API key management
  - Model creation and configuration
  - Chat completion and streaming

  ## Configuration API

      # Get API keys for different providers
      Jido.AI.api_key(:openai)
      Jido.AI.api_key(:anthropic)

      # Get model names with defaults
      Jido.AI.model_name(:openai)  # "gpt-4o"
      Jido.AI.model_name(:anthropic)  # "claude-3-5-sonnet-20241022"

      # Get provider configuration
      Jido.AI.provider_config(:openai)

      # Get any configuration key
      Jido.AI.config(:max_tokens, 1000)

  ## Model and Chat API

      # Create models - multiple formats supported
      {:ok, model} = Jido.AI.model("openrouter:anthropic/claude-3.5-sonnet")
      {:ok, model} = Jido.AI.model({:openai, model: "gpt-4o", temperature: 0.7})
      {:ok, model} = Jido.AI.model({:openrouter, model: "anthropic/claude-3.5-sonnet", max_tokens: 2000})

      # Text generation - flexible model specs
      {:ok, text} = Jido.AI.generate_text("openrouter:anthropic/claude-3.5-sonnet", "Hello!", [])
      {:ok, text} = Jido.AI.generate_text({:openrouter, model: "anthropic/claude-3.5-sonnet"}, "Tell me a joke", [])

      # Chat completions
      Jido.AI.chat(model, messages)
      Jido.AI.stream(model, messages)

  """

  alias Jido.AI.{Keyring, Model}

  # ===========================================================================
  # Configuration API - Simple facades for common operations
  # ===========================================================================

  @doc """
  Gets the API key for a specific provider.

  ## Parameters

    * `provider` - The AI provider (default: :openai)

  ## Examples

      Jido.AI.api_key(:openai)
      Jido.AI.api_key(:anthropic)

  """
  @spec api_key(atom()) :: String.t() | nil
  def api_key(provider \\ :openai) do
    key = :"#{provider}_api_key"
    Keyring.get(Keyring, key)
  end

  @doc """
  Gets the default model name for a specific provider.

  ## Parameters

    * `provider` - The AI provider (default: :openai)

  ## Examples

      Jido.AI.model_name(:openai)     # "gpt-4o"
      Jido.AI.model_name(:anthropic)  # "claude-3-5-sonnet-20241022"

  """
  @spec model_name(atom()) :: String.t()
  def model_name(provider \\ :openai) do
    default_model =
      case provider do
        :openai -> "gpt-4o"
        :anthropic -> "claude-3-5-sonnet-20241022"
        :azure -> "gpt-4o"
        :ollama -> "llama3.2"
        _ -> "gpt-4o"
      end

    key = :"#{provider}_model"
    Keyring.get(Keyring, key, default_model)
  end

  @doc """
  Gets the complete configuration for a specific provider.

  ## Parameters

    * `provider` - The AI provider

  ## Examples

      Jido.AI.provider_config(:openai)
      # %{api_key: "sk-...", model: "gpt-4o", base_url: "https://api.openai.com/v1"}

  """
  @spec provider_config(atom()) :: map()
  def provider_config(provider) do
    Keyring.get(Keyring, provider, %{})
  end

  @doc """
  Gets a configuration value with an optional default.

  This is the most general configuration accessor.

  ## Parameters

    * `key` - The configuration key (atom)
    * `default` - Default value if key not found (default: nil)

  ## Examples

      Jido.AI.config(:max_tokens, 1000)
      Jido.AI.config(:temperature, 0.7)

  """
  @spec config(atom(), term()) :: term()
  def config(key, default \\ nil) do
    Keyring.get(Keyring, key, default)
  end

  # ===========================================================================
  # Session Management - Direct delegation to Keyring
  # ===========================================================================

  @doc """
  Sets a session-specific configuration value.

  ## Parameters

    * `key` - The configuration key (atom)
    * `value` - The value to store

  ## Examples

      Jido.AI.set_session_value(:temperature, 0.9)

  """
  @spec set_session_value(atom(), term()) :: :ok
  def set_session_value(key, value) do
    Keyring.set_session_value(Keyring, key, value)
  end

  @doc """
  Gets a session-specific configuration value.

  ## Parameters

    * `key` - The configuration key (atom)
    * `pid` - Process ID (default: current process)

  """
  @spec get_session_value(atom(), pid()) :: term() | nil
  def get_session_value(key, pid \\ self()) do
    Keyring.get_session_value(Keyring, key, pid)
  end

  @doc """
  Clears a session-specific configuration value.

  ## Parameters

    * `key` - The configuration key (atom)
    * `pid` - Process ID (default: current process)

  """
  @spec clear_session_value(atom(), pid()) :: :ok
  def clear_session_value(key, pid \\ self()) do
    Keyring.clear_session_value(Keyring, key, pid)
  end

  @doc """
  Clears all session-specific configuration values for the current process.

  ## Parameters

    * `pid` - Process ID (default: current process)

  """
  @spec clear_all_session_values(pid()) :: :ok
  def clear_all_session_values(pid \\ self()) do
    Keyring.clear_all_session_values(Keyring, pid)
  end

  # ===========================================================================
  # Backward compatibility with cleaner names
  # ===========================================================================

  @doc """
  Gets a configuration value (alias for config/2).

  ## Examples

      Jido.AI.get(:my_setting)
      Jido.AI.get(:my_setting, "default")

  """
  @spec get(atom(), term()) :: term()
  def get(key, default \\ nil) do
    config(key, default)
  end

  @doc """
  Lists all available configuration keys.

  Returns a list of atoms representing available configuration keys.
  """
  @spec list_keys() :: [atom()]
  def list_keys do
    Keyring.list(Keyring)
  end

  # ===========================================================================
  # Model API - Developer sugar for creating models
  # ===========================================================================

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
  Currently supports OpenRouter provider.

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
         {:ok, provider_module} <- get_provider_module(model.provider) do
      # Merge model options with provided opts
      merged_opts = merge_model_options(model, opts)

      # Call the provider's generate_text function
      provider_module.generate_text(model.model, prompt, merged_opts)
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
          {:ok, Stream.t()} | {:error, term()}
  def stream_text(model_spec, prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    with {:ok, model} <- ensure_model_struct(model_spec),
         {:ok, provider_module} <- get_provider_module(model.provider) do
      # Merge model options with provided opts
      merged_opts = merge_model_options(model, opts)

      # Call the provider's stream_text function
      provider_module.stream_text(model.model, prompt, merged_opts)
    end
  end

  @doc false
  @spec ensure_model_struct(Model.t() | {atom(), keyword()} | String.t()) ::
          {:ok, Model.t()} | {:error, String.t()}
  defp ensure_model_struct(%Model{} = model), do: {:ok, model}
  defp ensure_model_struct(model_spec), do: model(model_spec)

  @doc false
  @spec get_provider_module(atom()) :: {:ok, atom()} | {:error, String.t()}
  defp get_provider_module(provider) do
    Jido.AI.Provider.Registry.get_provider(provider)
  end

  @doc false
  @spec merge_model_options(Model.t(), keyword()) :: keyword()
  defp merge_model_options(model, opts) do
    model_opts =
      []
      |> maybe_put(:temperature, model.temperature)
      |> maybe_put(:max_tokens, model.max_tokens)
      |> maybe_put(:api_key, model.api_key)

    # Provided opts take precedence over model defaults
    Keyword.merge(model_opts, opts)
  end

  @doc false
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
