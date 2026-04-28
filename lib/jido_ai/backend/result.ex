defmodule Jido.AI.Backend.Result do
  # covers: jido_ai.runtime_contracts.backend_normalization_boundary jido_ai.thread_context_projection.turn_normalization
  @moduledoc """
  Backend-neutral execution result.

  This result model captures the normalized output that later phases can project
  into canonical turn, signal, and runtime-event contracts without leaking raw
  transport structs above the backend boundary.
  """

  @operation_values [:text, :object, :embedding]

  @schema Zoi.struct(
            __MODULE__,
            %{
              backend: Zoi.atom() |> Zoi.nullish(),
              operation: Zoi.enum(@operation_values) |> Zoi.default(:text),
              content: Zoi.any() |> Zoi.nullish(),
              text: Zoi.string() |> Zoi.default(""),
              object: Zoi.any() |> Zoi.nullish(),
              embeddings: Zoi.list(Zoi.any()) |> Zoi.nullish(),
              tool_calls: Zoi.list(Zoi.any()) |> Zoi.default([]),
              usage: Zoi.map() |> Zoi.nullish(),
              model: Zoi.string() |> Zoi.nullish(),
              finish_reason: Zoi.any() |> Zoi.nullish(),
              message_metadata: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{}),
              raw: Zoi.any() |> Zoi.nullish()
            },
            coerce: true
          )

  @type operation :: :text | :object | :embedding
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put_new(:text, "")
      |> Map.put_new(:tool_calls, [])
      |> Map.put_new(:message_metadata, %{})
      |> Map.put_new(:metadata, %{})

    case Zoi.parse(@schema, attrs) do
      {:ok, result} -> result
      {:error, errors} -> raise ArgumentError, "invalid backend result: #{inspect(errors)}"
    end
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(_), do: %{}
end
