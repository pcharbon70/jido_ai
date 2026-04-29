defmodule Jido.AI.Backend.Request do
  # covers: jido_ai.core_runtime.additive_backend_selection jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Backend-neutral request envelope for LLM execution.

  The request shape intentionally carries prompt, message, tool, schema, and
  workspace context without assuming a specific transport such as ReqLLM or a
  CLI-oriented harness runtime.
  """

  @operation_values [:text, :object, :embedding]

  defmodule ToolIntent do
    @moduledoc false

    @schema Zoi.struct(
              __MODULE__,
              %{
                tools: Zoi.any() |> Zoi.nullish(),
                allowed_tools: Zoi.list(Zoi.string()) |> Zoi.default([]),
                tool_choice: Zoi.any() |> Zoi.nullish(),
                metadata: Zoi.map() |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec new(map() | keyword() | nil) :: t()
    def new(attrs \\ %{}) do
      attrs = attrs |> normalize_opts() |> Map.put_new(:metadata, %{})

      case Zoi.parse(@schema, attrs) do
        {:ok, tool_intent} -> tool_intent
        {:error, errors} -> raise ArgumentError, "invalid backend tool intent: #{inspect(errors)}"
      end
    end

    defp normalize_opts(nil), do: %{}
    defp normalize_opts(attrs) when is_list(attrs), do: Map.new(attrs)
    defp normalize_opts(attrs) when is_map(attrs), do: attrs
    defp normalize_opts(_), do: %{}
  end

  defmodule Workspace do
    @moduledoc false

    @schema Zoi.struct(
              __MODULE__,
              %{
                cwd: Zoi.string() |> Zoi.nullish(),
                session_id: Zoi.string() |> Zoi.nullish(),
                attachments: Zoi.list(Zoi.any()) |> Zoi.default([]),
                metadata: Zoi.map() |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec new(map() | keyword() | nil) :: t()
    def new(attrs \\ %{}) do
      attrs = attrs |> normalize_opts() |> Map.put_new(:metadata, %{})

      case Zoi.parse(@schema, attrs) do
        {:ok, workspace} -> workspace
        {:error, errors} -> raise ArgumentError, "invalid backend workspace: #{inspect(errors)}"
      end
    end

    defp normalize_opts(nil), do: %{}
    defp normalize_opts(attrs) when is_list(attrs), do: Map.new(attrs)
    defp normalize_opts(attrs) when is_map(attrs), do: attrs
    defp normalize_opts(_), do: %{}
  end

  @schema Zoi.struct(
            __MODULE__,
            %{
              request_id: Zoi.string() |> Zoi.nullish(),
              backend: Zoi.atom() |> Zoi.nullish(),
              operation: Zoi.enum(@operation_values) |> Zoi.default(:text),
              stream?: Zoi.boolean() |> Zoi.default(false),
              cancellable?: Zoi.boolean() |> Zoi.default(false),
              prompt: Zoi.string() |> Zoi.nullish(),
              messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
              system_prompt: Zoi.string() |> Zoi.nullish(),
              model: Zoi.any() |> Zoi.nullish(),
              timeout_ms: Zoi.integer() |> Zoi.nullish(),
              max_tokens: Zoi.integer() |> Zoi.nullish(),
              temperature: Zoi.number() |> Zoi.nullish(),
              response_schema: Zoi.any() |> Zoi.nullish(),
              inputs: Zoi.list(Zoi.any()) |> Zoi.default([]),
              tool_intent: Zoi.any() |> Zoi.nullish(),
              workspace: Zoi.any() |> Zoi.nullish(),
              backend_metadata: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
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
    attrs = normalize_attrs(attrs)

    case Zoi.parse(@schema, attrs) do
      {:ok, request} -> validate_operation!(request)
      {:error, errors} -> raise ArgumentError, "invalid backend request: #{inspect(errors)}"
    end
  end

  @doc """
  Returns true when the request relies on message history rather than a prompt-only payload.
  """
  @spec uses_message_history?(t()) :: boolean()
  def uses_message_history?(%__MODULE__{messages: [_ | _]}), do: true
  def uses_message_history?(%__MODULE__{}), do: false

  @doc """
  Returns true when the request expects local tool-calling support.
  """
  @spec needs_local_tools?(t()) :: boolean()
  def needs_local_tools?(%__MODULE__{tool_intent: %ToolIntent{} = tool_intent}) do
    tool_list = normalize_tool_list(tool_intent.tools)

    tool_list != [] or tool_intent.allowed_tools != [] or explicit_tool_choice?(tool_intent.tool_choice)
  end

  def needs_local_tools?(%__MODULE__{}), do: false

  @doc """
  Returns true when the request expects workspace-scoped execution context.
  """
  @spec needs_workspace?(t()) :: boolean()
  def needs_workspace?(%__MODULE__{workspace: %Workspace{} = workspace}) do
    not is_nil(workspace.cwd) or not is_nil(workspace.session_id) or workspace.attachments != [] or
      workspace.metadata != %{}
  end

  def needs_workspace?(%__MODULE__{}), do: false

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> maybe_normalize_tool_intent()
    |> maybe_normalize_workspace()
    |> Map.put_new(:messages, [])
    |> Map.put_new(:inputs, [])
    |> Map.put_new(:backend_metadata, %{})
    |> Map.put_new(:metadata, %{})
  end

  defp normalize_attrs(_), do: normalize_attrs(%{})

  defp maybe_normalize_tool_intent(attrs) do
    case Map.get(attrs, :tool_intent, Map.get(attrs, "tool_intent")) do
      nil -> attrs
      %ToolIntent{} = tool_intent -> put_field(attrs, :tool_intent, tool_intent)
      tool_intent -> put_field(attrs, :tool_intent, ToolIntent.new(tool_intent))
    end
  end

  defp maybe_normalize_workspace(attrs) do
    case Map.get(attrs, :workspace, Map.get(attrs, "workspace")) do
      nil -> attrs
      %Workspace{} = workspace -> put_field(attrs, :workspace, workspace)
      workspace -> put_field(attrs, :workspace, Workspace.new(workspace))
    end
  end

  defp put_field(attrs, key, value) do
    attrs
    |> Map.put(key, value)
    |> Map.put(Atom.to_string(key), value)
  end

  defp validate_operation!(%__MODULE__{operation: operation} = request) when operation in @operation_values, do: request

  defp validate_operation!(%__MODULE__{operation: operation}) do
    raise ArgumentError,
          "invalid backend request operation: #{inspect(operation)}; expected one of #{inspect(@operation_values)}"
  end

  defp normalize_tool_list(tools) when is_list(tools), do: tools
  defp normalize_tool_list(nil), do: []
  defp normalize_tool_list(_tools), do: [:tool]

  defp explicit_tool_choice?(nil), do: false
  defp explicit_tool_choice?(:auto), do: false
  defp explicit_tool_choice?(:none), do: false
  defp explicit_tool_choice?(_tool_choice), do: true
end
