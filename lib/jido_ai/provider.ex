defmodule Jido.AI.Provider do
  @moduledoc """
  Module for managing AI providers.

  This struct represents an AI provider with configuration and models
  as defined by the models.dev schema specification.
  """
  use TypedStruct

  alias Jido.AI.Model

  typedstruct do
    field(:id, String.t())
    field(:env, [String.t()])
    field(:name, String.t())
    field(:doc, String.t())
    field(:models, %{String.t() => Model.t()})
  end

  @schema NimbleOptions.new!([
    id: [type: :string, required: true],
    env: [type: {:list, :string}, required: true],
    name: [type: :string, required: true],
    doc: [type: :string, required: true],
    models: [type: :map, required: true]
  ])

  @doc """
  Validates that a provider struct conforms to the schema requirements using NimbleOptions.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(%__MODULE__{} = provider) do
    provider_map = Map.from_struct(provider)
    case NimbleOptions.validate(provider_map, @schema) do
      {:ok, _validated} -> {:ok, provider}
      error -> error
    end
  end
end
