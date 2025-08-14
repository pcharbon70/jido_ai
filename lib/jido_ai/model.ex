defmodule Jido.AI.Model do
  @moduledoc """
  Module for managing AI models.

  This struct represents an AI model with capabilities, pricing, and limitations
  as defined by the models.dev schema specification.
  """
  use TypedStruct

  @type modality :: :text | :audio | :image | :video | :pdf
  @type cost :: %{
          input: float(),
          output: float(),
          cache_read: float() | nil,
          cache_write: float() | nil
        }
  @type limit :: %{
          context: non_neg_integer(),
          output: non_neg_integer()
        }

  typedstruct do
    # Runtime fields for API calls
    field(:provider, atom())
    field(:model, String.t())
    field(:base_url, String.t())
    field(:api_key, String.t() | nil)
    field(:temperature, float() | nil)
    field(:max_tokens, non_neg_integer() | nil)
    field(:max_retries, non_neg_integer() | nil)

    # Metadata fields from models.dev schema
    field(:id, String.t())
    field(:name, String.t())
    field(:attachment, boolean())
    field(:reasoning, boolean())
    field(:supports_temperature, boolean())
    field(:tool_call, boolean())
    field(:knowledge, String.t() | nil)
    field(:release_date, String.t())
    field(:last_updated, String.t())

    field(:modalities, %{
      input: [modality()],
      output: [modality()]
    })

    field(:open_weights, boolean())
    field(:cost, cost() | nil)
    field(:limit, limit())
  end

  @cost_schema NimbleOptions.new!(
                 input: [type: {:or, [:integer, :float]}, required: true],
                 output: [type: {:or, [:integer, :float]}, required: true],
                 cache_read: [type: {:or, [:integer, :float]}, required: false],
                 cache_write: [type: {:or, [:integer, :float]}, required: false]
               )

  @limit_schema NimbleOptions.new!(
                  context: [type: :non_neg_integer, required: true],
                  output: [type: :non_neg_integer, required: true]
                )

  @schema NimbleOptions.new!(
            id: [type: :string, required: true],
            name: [type: :string, required: true],
            attachment: [type: :boolean, required: true],
            reasoning: [type: :boolean, required: true],
            supports_temperature: [type: :boolean, required: true],
            tool_call: [type: :boolean, required: true],
            knowledge: [type: :string, required: false],
            release_date: [type: :string, required: true],
            last_updated: [type: :string, required: true],
            modalities: [type: :map, required: true],
            open_weights: [type: :boolean, required: true],
            cost: [type: {:custom, __MODULE__, :validate_cost, []}, required: false],
            limit: [type: {:custom, __MODULE__, :validate_limit, []}, required: true]
          )

  @doc """
  Validates that a model struct conforms to the schema requirements using NimbleOptions.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(%__MODULE__{} = model) do
    model_map = Map.from_struct(model)

    case NimbleOptions.validate(model_map, @schema) do
      {:ok, _validated} -> {:ok, model}
      error -> error
    end
  end

  @doc """
  Validates date format (YYYY-MM or YYYY-MM-DD).
  """
  def validate_date_format(nil), do: {:ok, nil}

  def validate_date_format(value) when is_binary(value) do
    if Regex.match?(~r/^\d{4}-\d{2}(-\d{2})?$/, value) do
      {:ok, value}
    else
      {:error, "must be in YYYY-MM or YYYY-MM-DD format"}
    end
  end

  def validate_date_format(_), do: {:error, "must be a string or nil"}

  @doc """
  Validates cost structure with required input/output and optional cache fields.
  """
  def validate_cost(nil), do: {:ok, nil}

  def validate_cost(cost) when is_map(cost) do
    NimbleOptions.validate(cost, @cost_schema)
  end

  def validate_cost(_), do: {:error, "must be a map"}

  @doc """
  Validates limit structure with context and output fields.
  """
  def validate_limit(limit) when is_map(limit) do
    NimbleOptions.validate(limit, @limit_schema)
  end

  def validate_limit(_), do: {:error, "must be a map"}

  @doc """
  Creates a model from various input formats.

  Supports:
  - Existing Model struct
  - Tuple format: `{provider, opts}` where provider is atom and opts is keyword list
  - String format: `"provider:model"` (e.g., "openrouter:anthropic/claude-3.5-sonnet")

  ## Examples

      Model.from(%Model{provider: :openai, model: "gpt-4"})
      Model.from({:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7})
      Model.from("openrouter:anthropic/claude-3.5-sonnet")

  """
  @spec from(t() | {atom(), keyword()} | String.t()) :: {:ok, t()} | {:error, String.t()}
  def from(%__MODULE__{} = model), do: {:ok, model}

  def from({provider, opts}) when is_atom(provider) and is_list(opts) do
    model_name = Keyword.get(opts, :model)

    if is_nil(model_name) do
      {:error, "model is required in options"}
    else
      case get_provider_info(provider) do
        {:ok, base_url} ->
          model = %__MODULE__{
            provider: provider,
            model: model_name,
            base_url: base_url,
            temperature: Keyword.get(opts, :temperature),
            max_tokens: Keyword.get(opts, :max_tokens),
            max_retries: Keyword.get(opts, :max_retries),
            api_key: Keyword.get(opts, :api_key),
            # Defaults for metadata fields
            id: to_string(model_name),
            name: to_string(model_name),
            attachment: false,
            reasoning: false,
            supports_temperature: true,
            tool_call: false,
            release_date: "2024-01",
            last_updated: "2024-01",
            modalities: %{input: [:text], output: [:text]},
            open_weights: false,
            limit: %{context: 128_000, output: 4096}
          }

          {:ok, model}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def from(provider_model_string) when is_binary(provider_model_string) do
    case String.split(provider_model_string, ":", parts: 2) do
      [provider_str, model_name] ->
        try do
          provider = String.to_existing_atom(provider_str)
          from({provider, [model: model_name]})
        rescue
          ArgumentError ->
            {:error, "Unknown provider: #{provider_str}"}
        end

      _ ->
        {:error, "Invalid model specification. Expected format: 'provider:model'"}
    end
  end

  def from(_), do: {:error, "Invalid model specification"}

  @doc false
  @spec get_provider_info(atom()) :: {:ok, String.t()} | {:error, String.t()}
  defp get_provider_info(provider) do
    case provider do
      :openai -> {:ok, "https://api.openai.com/v1"}
      :anthropic -> {:ok, "https://api.anthropic.com/v1"}
      :openrouter -> {:ok, "https://openrouter.ai/api/v1"}
      :cloudflare -> {:ok, "https://api.cloudflare.com/client/v4/accounts"}
      :google -> {:ok, "https://generativelanguage.googleapis.com/v1"}
      _ -> {:error, "No adapter found for provider #{provider}"}
    end
  end
end
