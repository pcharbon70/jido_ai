defmodule Jido.AI.Backend.Event do
  # covers: jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Backend-neutral event envelope for streaming and long-running execution.

  Different transports can emit different progress signals, but they should be
  projected into this intermediate shape before being translated into canonical
  Jido.AI runtime events.
  """

  @kind_values [
    :started,
    :delta,
    :thinking,
    :tool_call,
    :tool_result,
    :usage,
    :completed,
    :failed,
    :cancelled,
    :metadata
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              at_ms: Zoi.integer(),
              backend: Zoi.atom() |> Zoi.nullish(),
              request_id: Zoi.string() |> Zoi.nullish(),
              operation: Zoi.enum([:text, :object, :embedding]) |> Zoi.default(:text),
              kind: Zoi.atom(),
              data: Zoi.map() |> Zoi.default(%{}),
              raw: Zoi.any() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc """
  Creates a new backend event envelope.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:id, "bevt_#{Jido.Util.generate_id()}")
      |> Map.put_new(:at_ms, System.system_time(:millisecond))
      |> Map.put_new(:data, %{})

    case Zoi.parse(@schema, attrs) do
      {:ok, event} -> validate_kind!(event)
      {:error, errors} -> raise ArgumentError, "invalid backend event: #{inspect(errors)}"
    end
  end

  defp validate_kind!(%__MODULE__{kind: kind} = event) when kind in @kind_values, do: event

  defp validate_kind!(%__MODULE__{kind: kind}) do
    raise ArgumentError,
          "invalid backend event kind: #{inspect(kind)}; expected one of #{inspect(@kind_values)}"
  end
end
