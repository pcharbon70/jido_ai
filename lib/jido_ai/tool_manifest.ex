defmodule Jido.AI.ToolManifest do
  # covers: jido_ai.actions.tool_calling_loop_contract jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Backend-neutral tool manifest for Jido.Action integrations.

  A tool manifest captures the stable internal description of a callable tool
  without committing to a transport-specific representation such as
  `ReqLLM.Tool`.
  """

  alias Jido.Action.Schema, as: ActionSchema

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(),
              description: Zoi.string(),
              module: Zoi.atom(),
              parameter_schema: Zoi.map(),
              strict: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs = normalize_attrs(attrs)

    case Zoi.parse(@schema, attrs) do
      {:ok, manifest} -> manifest
      {:error, errors} -> raise ArgumentError, "invalid tool manifest: #{inspect(errors)}"
    end
  end

  @doc """
  Builds a canonical manifest from one Jido.Action module.
  """
  @spec from_action(module(), keyword()) :: t()
  def from_action(action_module, opts \\ []) when is_atom(action_module) do
    validate_action_module!(action_module)

    name = apply_prefix(action_module.name(), Keyword.get(opts, :prefix))
    strict = Keyword.get_lazy(opts, :strict, fn -> infer_strict?(action_module) end)

    metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> normalize_metadata()
      |> maybe_put_metadata(:category, action_category(action_module))

    new(%{
      name: name,
      description: action_module.description(),
      module: action_module,
      parameter_schema: build_json_schema(action_module.schema()),
      strict: strict,
      metadata: metadata
    })
  end

  @doc """
  Builds canonical manifests from a list of Jido.Action modules.
  """
  @spec from_actions([module()], keyword()) :: [t()]
  def from_actions(action_modules, opts \\ []) when is_list(action_modules) do
    prefix = Keyword.get(opts, :prefix)
    filter_fn = Keyword.get(opts, :filter)
    metadata = Keyword.get(opts, :metadata, %{})
    explicit_strict = Keyword.fetch(opts, :strict)

    manifests =
      action_modules
      |> maybe_filter(filter_fn)
      |> Enum.map(fn module ->
        strict_opts =
          case explicit_strict do
            {:ok, value} -> [strict: value]
            :error -> []
          end

        from_action(module, [prefix: prefix, metadata: metadata] ++ strict_opts)
      end)

    ensure_unique_names!(manifests)
  end

  defp ensure_unique_names!(manifests) do
    names = Enum.map(manifests, & &1.name)
    duplicates = names -- Enum.uniq(names)

    if duplicates != [] do
      raise ArgumentError,
            "Duplicate tool names detected: #{inspect(Enum.uniq(duplicates))}. " <>
              "Each action must have a unique name."
    end

    manifests
  end

  defp validate_action_module!(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        raise ArgumentError, "tool manifest action module is not loaded: #{inspect(module)}"

      not function_exported?(module, :name, 0) ->
        raise ArgumentError, "tool manifest action module is missing name/0: #{inspect(module)}"

      not function_exported?(module, :description, 0) ->
        raise ArgumentError, "tool manifest action module is missing description/0: #{inspect(module)}"

      not function_exported?(module, :schema, 0) ->
        raise ArgumentError, "tool manifest action module is missing schema/0: #{inspect(module)}"

      true ->
        :ok
    end
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(_), do: %{}

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(_), do: %{}

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put_new(metadata, key, value)

  defp maybe_filter(modules, nil), do: modules
  defp maybe_filter(modules, filter_fn) when is_function(filter_fn, 1), do: Enum.filter(modules, filter_fn)

  defp build_json_schema(schema) do
    case schema |> action_schema_to_json_schema() |> enforce_no_additional_properties() do
      empty when empty == %{} ->
        %{"type" => "object", "properties" => %{}, "required" => [], "additionalProperties" => false}

      json_schema ->
        json_schema
    end
  end

  defp action_schema_to_json_schema(schema) do
    cond do
      function_exported?(ActionSchema, :to_json_schema, 2) ->
        apply(ActionSchema, :to_json_schema, [schema, [strict: true]])

      function_exported?(ActionSchema, :to_json_schema, 1) ->
        ActionSchema.to_json_schema(schema)

      true ->
        %{}
    end
  end

  defp enforce_no_additional_properties(schema) when is_map(schema) do
    schema
    |> Enum.map(fn {key, value} -> {key, enforce_no_additional_properties(value)} end)
    |> Map.new()
    |> maybe_put_additional_properties_false()
  end

  defp enforce_no_additional_properties(schema) when is_list(schema) do
    Enum.map(schema, &enforce_no_additional_properties/1)
  end

  defp enforce_no_additional_properties(schema), do: schema

  defp maybe_put_additional_properties_false(%{"type" => "object"} = schema) do
    Map.put_new(schema, "additionalProperties", false)
  end

  defp maybe_put_additional_properties_false(%{"properties" => _properties} = schema) do
    Map.put_new(schema, "additionalProperties", false)
  end

  defp maybe_put_additional_properties_false(schema), do: schema

  defp infer_strict?(module) do
    if function_exported?(module, :strict?, 0), do: module.strict?(), else: false
  end

  defp action_category(module) do
    if function_exported?(module, :category, 0), do: module.category(), else: nil
  end

  defp apply_prefix(name, nil), do: name
  defp apply_prefix(name, prefix) when is_binary(prefix), do: prefix <> name
end
