defmodule Jido.AI.Provider.Registry do
  @moduledoc """
  Fast, read-only registry for AI provider modules using persistent_term.

  This module provides O(1) lookup for provider modules and handles
  automatic discovery and registration at compile/runtime.
  """

  require Logger

  @registry_key {__MODULE__, :providers}

  @doc """
  Gets the provider module for the given provider ID.

  Returns the module atom for the provider, or an error if not found.

  ## Examples

      iex> Jido.AI.Provider.Registry.get_provider(:openrouter)
      {:ok, Jido.AI.Provider.OpenRouter}

      iex> Jido.AI.Provider.Registry.get_provider(:nonexistent)
      {:error, "Provider not found: nonexistent"}

  """
  @spec get_provider(atom()) :: {:ok, module()} | {:error, Exception.t()}
  def get_provider(provider_id) do
    case :persistent_term.get(@registry_key, %{}) do
      %{^provider_id => module} ->
        {:ok, module}

      _ ->
        {:error, Jido.AI.Error.Invalid.Parameter.exception(parameter: "provider #{provider_id}")}
    end
  end

  @doc """
  Lists all registered provider IDs.

  ## Examples

      iex> Jido.AI.Provider.Registry.list_providers()
      [:openrouter, :openai, :anthropic]

  """
  @spec list_providers() :: [atom()]
  def list_providers do
    :persistent_term.get(@registry_key, %{})
    |> Map.keys()
  end

  @doc """
  Registers a provider module with the given ID.

  This is typically called during application startup or provider module loading.

  ## Examples

      iex> Jido.AI.Provider.Registry.register(:openrouter, Jido.AI.Provider.OpenRouter)
      :ok

  """
  @spec register(atom(), module()) :: :ok
  def register(provider_id, module) do
    current_providers = :persistent_term.get(@registry_key, %{})
    updated_providers = Map.put(current_providers, provider_id, module)
    :persistent_term.put(@registry_key, updated_providers)
    # Logger.debug("Registered AI provider: #{provider_id} -> #{module}")
    :ok
  end

  @doc """
  Initializes the provider registry by discovering and registering all provider modules.

  This function scans for modules that implement the `Jido.AI.Provider.Base` behaviour
  and registers them automatically.
  """
  @spec initialize() :: :ok
  def initialize do
    # Discover provider modules
    providers = discover_providers()

    # Register each provider
    registry_map =
      providers
      |> Enum.map(fn module ->
        try do
          provider_info = module.provider_info()
          {provider_info.id, module}
        rescue
          e ->
            Logger.warning("Failed to get provider info from #{module}: #{inspect(e)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    # Store in persistent_term
    :persistent_term.put(@registry_key, registry_map)

    :ok
  end

  @spec reload() :: :ok
  def reload, do: initialize()

  @doc """
  Clears the provider registry.

  Mainly useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.erase(@registry_key)
    :ok
  end

  # Private functions

  @spec discover_providers() :: [module()]
  defp discover_providers do
    # Get all loaded modules that implement our behaviour
    :application.get_key(:jido_ai, :modules)
    |> case do
      {:ok, modules} -> modules
      :undefined -> []
    end
    |> Enum.filter(&provider_module?/1)
  end

  @spec provider_module?(module()) :: boolean()
  defp provider_module?(module) do
    # Check if module implements Jido.AI.Provider.Base behaviour
    try do
      behaviours = module.__info__(:attributes)[:behaviour] || []
      Jido.AI.Provider.Base in behaviours
    rescue
      _ -> false
    end
  end
end
