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
    field(:id, String.t())
    field(:name, String.t())
    field(:attachment, boolean())
    field(:reasoning, boolean())
    field(:temperature, boolean())
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

  @cost_schema NimbleOptions.new!([
    input: [type: {:or, [:integer, :float]}, required: true],
    output: [type: {:or, [:integer, :float]}, required: true],
    cache_read: [type: {:or, [:integer, :float]}, required: false],
    cache_write: [type: {:or, [:integer, :float]}, required: false]
  ])

  @limit_schema NimbleOptions.new!([
    context: [type: :non_neg_integer, required: true],
    output: [type: :non_neg_integer, required: true]
  ])

  @schema NimbleOptions.new!([
    id: [type: :string, required: true],
    name: [type: :string, required: true],
    attachment: [type: :boolean, required: true],
    reasoning: [type: :boolean, required: true],
    temperature: [type: :boolean, required: true],
    tool_call: [type: :boolean, required: true],
    knowledge: [type: :string, required: false, validate: {__MODULE__, :validate_date_format}],
    release_date: [type: :string, required: true, validate: {__MODULE__, :validate_date_format}],
    last_updated: [type: :string, required: true, validate: {__MODULE__, :validate_date_format}],
    modalities: [
      type: {:map, [
        input: {:list, {:in, [:text, :audio, :image, :video, :pdf]}},
        output: {:list, {:in, [:text, :audio, :image, :video, :pdf]}}
      ]},
      required: true
    ],
    open_weights: [type: :boolean, required: true],
    cost: [type: {:custom, __MODULE__, :validate_cost, []}, required: false],
    limit: [type: {:custom, __MODULE__, :validate_limit, []}, required: true]
  ])


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


end
