defmodule Jido.AI.Config do
  @moduledoc """
  Configuration management with Application environment overrides.

  Provides a simple interface for getting provider-specific configuration
  with Application environment precedence over Keyring values.

  ## Configuration Format

  Configuration should be scoped by provider ID with a global default provider:

      config :jido_ai,
        default_provider: :openrouter,
        openrouter: [
          base_url: "https://custom-openrouter.ai/api/v1",
          api_key: "or-...",
          default_model: "anthropic/claude-3.5-sonnet"
        ],
        openai: [
           api_key: "sk-...",
           base_url: "https://custom-openai.com/v1",
           default_model: "gpt-4o"
         ],
         http_client: Req  # Must be Req or Req.Test only

  ## Usage

      # Get provider-specific config keyword list
      Config.get_provider_config(:openrouter)
      # [base_url: "https...", api_key: "or-...", default_model: "..."]

      # Get specific provider setting
      Config.get_provider_setting(:openrouter, :base_url)
      # "https://custom-openrouter.ai/api/v1"

      # Get API key (with Keyring fallback)
      Config.get_api_key(:openrouter)
      # "or-..."

      # Get default provider
      Config.get_default_provider()
      # :openrouter

      # Get HTTP client (for testing)
      Config.get_http_client()
      # Req (default) or Req.Test

  """

  alias Jido.AI.Keyring

  @env_app :jido_ai
  @config_default_provider :default_provider
  @config_api_key :api_key
  @config_http_client :http_client
  @config_receive_timeout :receive_timeout
  @config_pool_timeout :pool_timeout
  @config_stream_inactivity_timeout :stream_inactivity_timeout

  @doc """
  Gets the complete configuration keyword list for a provider.

  Checks Application environment first under the provider ID,
  with no defaults - returns empty list if not configured.

  ## Parameters

    * `provider` - The provider atom (e.g., :openrouter, :openai)

  ## Examples

      Config.get_provider_config(:openrouter)
      # [base_url: "https...", api_key: "or-...", default_model: "..."]

  """
  @spec get_provider_config(atom()) :: keyword()
  def get_provider_config(provider) when is_atom(provider) do
    case Application.get_env(@env_app, provider) do
      config when is_list(config) -> config
      _ -> []
    end
  end

  @doc """
  Gets a specific setting for a provider.

  Checks Application environment first, returns nil if not found.
  No defaults - defaults should come from Provider modules.

  ## Parameters

    * `provider` - The provider atom
    * `setting` - The setting key atom (e.g., :base_url, :default_model, :api_key)

  ## Examples

      Config.get_provider_setting(:openrouter, :base_url)
      Config.get_provider_setting(:openai, :default_model)

  """
  @spec get_provider_setting(atom(), atom()) :: term() | nil
  def get_provider_setting(provider, setting) when is_atom(provider) and is_atom(setting) do
    provider
    |> get_provider_config()
    |> Keyword.get(setting)
  end

  @doc """
  Gets an API key for a provider with Keyring fallback.

  First checks Application environment under provider config,
  then falls back to Keyring with standard key format.

  ## Parameters

    * `provider` - The provider atom
    * `keyring_server` - The Keyring server (default: Jido.AI.Keyring)

  ## Examples

      Config.get_api_key(:openrouter)
      Config.get_api_key(:openai, MyKeyring)

  """
  @spec get_api_key(atom(), GenServer.server()) :: String.t() | nil
  def get_api_key(provider, keyring_server \\ Keyring) when is_atom(provider) do
    case get_provider_setting(provider, @config_api_key) do
      nil ->
        # Fallback to Keyring with standard format
        key = :"#{provider}_api_key"
        Keyring.get(keyring_server, key)

      api_key when is_binary(api_key) ->
        api_key

      _ ->
        nil
    end
  end

  @doc """
  Gets the default provider atom.

  Returns the globally configured default provider, or nil if not set.

  ## Examples

      Config.get_default_provider()
      # :openrouter

  """
  @spec get_default_provider() :: atom() | nil
  def get_default_provider do
    case Application.get_env(@env_app, @config_default_provider) do
      provider when is_atom(provider) -> provider
      _ -> nil
    end
  end

  @doc """
  Gets the HTTP client module for making requests.

  Returns the configured HTTP client module. Only `Req` and `Req.Test` 
  are supported - other modules will break the HTTP request logic.

  ## Supported HTTP Clients

    * `Req` - Production HTTP client (default)
    * `Req.Test` - Test HTTP client with mocking capabilities

  ## Examples

      Config.get_http_client()
      # Req (default)

      # In tests - configure Req.Test for mocking
      Application.put_env(:jido_ai, :http_client, Req.Test)
      Config.get_http_client()
      # Req.Test

  ## Warning

  Do not use custom HTTP client modules as they must implement the exact
  same interface as Req (post/2, stream!/2, etc.) to work correctly.

  """
  @spec get_http_client() :: module()
  def get_http_client do
    Application.get_env(@env_app, @config_http_client, Req)
  end

  @doc """
  Gets a configuration value with Application environment precedence.

  General purpose config getter that checks Application env first,
  then falls back to Keyring.

  ## Parameters

    * `key` - The configuration key atom
    * `default` - Default value if not found (default: nil)
    * `keyring_server` - The Keyring server (default: Jido.AI.Keyring)

  ## Examples

      Config.get(:max_tokens, 1000)
      Config.get(:temperature, 0.7)

  """
  @spec get(atom(), term(), GenServer.server()) :: term()
  def get(key, default \\ nil, keyring_server \\ Keyring) when is_atom(key) do
    case Application.get_env(@env_app, key) do
      nil -> Keyring.get(keyring_server, key, default)
      value -> value
    end
  end

  @doc """
  Gets a timeout configuration value.

  Simplified getter for timeout-specific configuration values with
  Application environment precedence.

  ## Parameters

    * `key` - The timeout configuration key atom
    * `default` - Default timeout value in milliseconds

  ## Examples

      Config.get_timeout(:receive_timeout, 5000)
      Config.get_timeout(:pool_timeout, 30_000)

  """
  @spec get_timeout(atom(), integer()) :: integer()
  def get_timeout(key, default) do
    Application.get_env(@env_app, key, default)
  end

  @spec get_receive_timeout(integer()) :: integer()
  def get_receive_timeout(default \\ 60_000) do
    get_timeout(@config_receive_timeout, default)
  end

  @spec get_pool_timeout(integer()) :: integer()
  def get_pool_timeout(default \\ 30_000) do
    get_timeout(@config_pool_timeout, default)
  end

  @spec get_stream_inactivity_timeout(integer()) :: integer()
  def get_stream_inactivity_timeout(default \\ 15_000) do
    get_timeout(@config_stream_inactivity_timeout, default)
  end
end
