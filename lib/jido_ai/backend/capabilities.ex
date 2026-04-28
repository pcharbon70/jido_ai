defmodule Jido.AI.Backend.Capabilities do
  # covers: package.jido_ai.explicit_policy_boundaries jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Declares the features a backend explicitly supports.

  Capability checks are expected to run before transport-specific execution so
  unsupported combinations fail fast with typed errors.
  """

  alias Jido.AI.Backend.Request

  @capability_values [
    :text_generation,
    :streaming,
    :structured_output,
    :embeddings,
    :local_tools,
    :cancellation,
    :message_history,
    :workspace_execution
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              text_generation: Zoi.boolean() |> Zoi.default(false),
              streaming: Zoi.boolean() |> Zoi.default(false),
              structured_output: Zoi.boolean() |> Zoi.default(false),
              embeddings: Zoi.boolean() |> Zoi.default(false),
              local_tools: Zoi.boolean() |> Zoi.default(false),
              cancellation: Zoi.boolean() |> Zoi.default(false),
              message_history: Zoi.boolean() |> Zoi.default(false),
              workspace_execution: Zoi.boolean() |> Zoi.default(false)
            },
            coerce: true
          )

  @type capability ::
          :text_generation
          | :streaming
          | :structured_output
          | :embeddings
          | :local_tools
          | :cancellation
          | :message_history
          | :workspace_execution

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs =
      case attrs do
        attrs when is_list(attrs) -> Map.new(attrs)
        attrs when is_map(attrs) -> attrs
        _ -> %{}
      end

    case Zoi.parse(@schema, attrs) do
      {:ok, capabilities} -> capabilities
      {:error, errors} -> raise ArgumentError, "invalid backend capabilities: #{inspect(errors)}"
    end
  end

  @spec supports?(t(), capability()) :: boolean()
  def supports?(%__MODULE__{} = capabilities, capability) when capability in @capability_values do
    Map.fetch!(capabilities, capability)
  end

  @doc """
  Returns the capability set required by the request.
  """
  @spec required_for(Request.t()) :: [capability()]
  def required_for(%Request{} = request) do
    []
    |> require_for_operation(request.operation)
    |> require_if(request.stream?, :streaming)
    |> require_if(request.cancellable?, :cancellation)
    |> require_if(Request.uses_message_history?(request), :message_history)
    |> require_if(Request.needs_local_tools?(request), :local_tools)
    |> require_if(Request.needs_workspace?(request), :workspace_execution)
    |> Enum.uniq()
  end

  @doc """
  Validates the request against the advertised capability set.
  """
  @spec validate_request(t(), Request.t(), keyword()) :: :ok | {:error, term()}
  def validate_request(%__MODULE__{} = capabilities, %Request{} = request, opts \\ []) do
    backend = Keyword.get(opts, :backend, request.backend)

    case Enum.find(required_for(request), &(not supports?(capabilities, &1))) do
      nil ->
        :ok

      missing_capability ->
        {:error,
         Jido.AI.Error.Backend.UnsupportedCapability.exception(
           backend: backend,
           capability: missing_capability,
           operation: request.operation
         )}
    end
  end

  defp require_for_operation(capabilities, :text), do: [:text_generation | capabilities]
  defp require_for_operation(capabilities, :object), do: [:structured_output | capabilities]
  defp require_for_operation(capabilities, :embedding), do: [:embeddings | capabilities]

  defp require_if(capabilities, true, capability), do: [capability | capabilities]
  defp require_if(capabilities, false, _capability), do: capabilities
end
