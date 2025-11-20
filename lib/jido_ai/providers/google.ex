defmodule Jido.AI.Provider.Google do
  @moduledoc """
  Adapter for the Google Gemini API provider.

  Implements the ProviderBehavior for Google's OpenAI-compatible API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Model
  alias Jido.AI.Provider

  @base_url "https://generativelanguage.googleapis.com/v1beta/models/"
  @provider_id :google

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "Google",
      description: "Google Gemini API with OpenAI-compatible interface",
      type: :direct,
      api_base_url: @base_url
    }
  end

  @impl true
  @doc """
  Lists available models from the Model Registry.

  This function delegates to the Model Registry which provides access to
  Google models through ReqLLM integration.

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
  @doc """
  Normalizes a model ID to ensure it's in the correct format for Google Gemini.

  ## Options
    - No specific options for this method

  Returns a tuple with {:ok, normalized_id} on success or {:error, reason} on failure.
  """
  def normalize(model, _opts \\ []) do
    # Google Gemini models have format like "models/gemini-2.0-flash" or "gemini-2.0-flash"
    # Strip the models/ prefix if present
    {:ok, String.replace(model, "models/", "")}
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
       id: opts[:model] || "google_default",
       name: opts[:model_name] || "Google Gemini Model",
       provider: :google
     }}
  end

  @impl true
  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This function validates the options, sets defaults, and creates a fully populated
  model struct for the Google provider.

  ## Parameters
    - opts: Map or keyword list of options for building the model

  ## Returns
    - {:ok, %Jido.AI.Model{}} on success
    - {:error, reason} on failure
  """
  def build(opts) when is_list(opts) do
    # Convert keyword list to map
    build(Map.new(opts))
  end

  def build(opts) when is_map(opts) do
    # Extract or generate an API key
    _api_key = Map.get(opts, "api_key") || Map.get(opts, :api_key)

    # Get model from opts
    model = Map.get(opts, "name") || Map.get(opts, :model)

    # Validate model
    if is_nil(model) do
      {:error, "model is required for Google Gemini models"}
    else
      # Strip models/ prefix if present
      model = String.replace(model, "models/", "")

      # Create ReqLLM.Model directly
      # Convert Map opts to Keyword list for ReqLLM
      keyword_opts = if is_map(opts), do: Map.to_list(opts), else: opts
      ReqLLM.Model.from({:google, model, keyword_opts})
    end
  end

  @impl true
  def transform_model_to_clientmodel(_client_atom, _model) do
    {:error, "Not implemented yet"}
  end
end
