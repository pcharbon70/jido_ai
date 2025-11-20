defmodule Jido.AI.Provider.Cloudflare do
  @moduledoc """
  Adapter for the Cloudflare AI provider.

  Implements the ProviderBehavior for Cloudflare's AI API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Helpers

  @base_url "https://api.cloudflare.com/client/v4/accounts"
  @provider_id :cloudflare

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "Cloudflare",
      description: "Cloudflare's AI Gateway provides access to multiple AI models",
      type: :proxy,
      api_base_url: @base_url,
      requires_api_key: true
    }
  end

  @impl true
  @doc """
  Lists available models from the Model Registry.

  This function delegates to the Model Registry which provides access to
  Cloudflare models through ReqLLM integration.

  ## Options
    - refresh: boolean - Ignored (models come from ReqLLM)

  Returns a tuple with {:ok, models} on success or {:error, reason} on failure.
  """
  def list_models(_opts \\ []) do
    # Delegate to Model Registry which gets models from ReqLLM
    alias Jido.AI.Model.Registry
    Registry.list_models(@provider_id)
  end

  @impl true
  @doc """
  Fetches a specific model by ID from the Model Registry.

  ## Options
    - refresh: boolean - Ignored (models come from ReqLLM)

  Returns a tuple with {:ok, model} on success or {:error, reason} on failure.
  """
  def model(model_id, _opts \\ []) do
    # Delegate to Model Registry
    alias Jido.AI.Model.Registry

    case Registry.list_models(@provider_id) do
      {:ok, models} ->
        # ReqLLM.Model may have id in metadata or use .model field
        case Enum.find(models, fn m ->
          m_id = Map.get(m._metadata || %{}, :id) || m.model
          m_name = Map.get(m._metadata || %{}, "name")
          m_id == model_id or m_name == model_id or m.model == model_id
        end) do
          nil -> {:error, "Model not found: #{model_id}"}
          model -> {:ok, model}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def normalize(model, _opts \\ []) do
    {:ok, model}
  end

  @impl true
  def base_url do
    @base_url
  end

  @impl true
  def request_headers(_opts) do
    # Headers are now handled internally by ReqLLM
    # This function is kept for adapter behavior compatibility
    %{"Content-Type" => "application/json"}
  end

  @impl true
  def validate_model_opts(opts) do
    {:ok,
     %Model{
       id: opts[:model] || "cloudflare_default",
       name: opts[:model_name] || "Cloudflare Model",
       provider: :cloudflare
     }}
  end

  @impl true
  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This function validates the options, sets defaults, and creates a fully populated
  model struct for the Cloudflare provider.

  ## Parameters
    - opts: Keyword list of options for building the model

  ## Returns
    - {:ok, %Jido.AI.Model{}} on success
    - {:error, reason} on failure
  """
  def build(opts) do
    # Extract or generate an API key
    _api_key = Helpers.get_api_key(opts, "CLOUDFLARE_API_KEY", :cloudflare_api_key)

    # Get model from opts
    model = Keyword.get(opts, :model)

    # Validate model
    if is_nil(model) do
      {:error, "model is required for Cloudflare models"}
    else
      # Create ReqLLM.Model directly
      ReqLLM.Model.from({:cloudflare, model, opts})
    end
  end

  @impl true
  def transform_model_to_clientmodel(_client_atom, _model) do
    {:error, "Not implemented yet"}
  end
end
