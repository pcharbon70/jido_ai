defmodule Jido.AI.ToolAdapter do
  # covers: jido_ai.actions.tool_calling_loop_contract jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Adapts canonical Jido.AI tool manifests into ReqLLM transport structs.

  This module keeps `ReqLLM.Tool` conversion as an edge concern. The canonical
  internal tool description is `Jido.AI.ToolManifest`, which can be derived from
  `Jido.Action` modules and then projected into transport-specific tool structs
  only when a backend requires that representation.

  ## Design

  - **Manifest-first**: Jido actions are normalized into `Jido.AI.ToolManifest`
  - **Adapter pattern**: Converts tool manifests into `ReqLLM.Tool` structs
  - **Execution stays local**: Jido owns tool execution via runtime actions/directives

  ## Usage

      # Convert action modules to ReqLLM tools
      tools = Jido.AI.ToolAdapter.from_actions([
        MyApp.Actions.Calculator,
        MyApp.Actions.Search
      ])

      # With options
      tools = Jido.AI.ToolAdapter.from_actions(actions,
        prefix: "myapp_",
        filter: fn mod -> mod.category() == :search end
      )

      # Use in LLM call
      ReqLLM.stream_text(model, messages, tools: tools)
  """

  alias Jido.AI.ToolManifest

  # ============================================================================
  # Action Conversion
  # ============================================================================

  @doc """
  Converts a list of Jido.Action modules into ReqLLM.Tool structs.

  The returned tools use a noop callback—they're purely for describing available
  actions to the LLM. Actual execution happens via `Jido.AI.Directive.ToolExec`.

  ## Arguments

    * `action_modules` - List of modules implementing the `Jido.Action` behaviour
    * `opts` - Optional keyword list of options

  ## Options

    * `:prefix` - String prefix to add to all tool names (e.g., `"myapp_"`)
    * `:filter` - Function `(module -> boolean)` to filter which actions to include
    * `:strict` - Whether to enable strict mode on the tools. When not set,
      auto-detects based on each action's `strict?/0` callback (defaults to `false`).

  ## Returns

    A list of `ReqLLM.Tool` structs

  ## Examples

      # Basic usage
      tools = Jido.AI.ToolAdapter.from_actions([MyApp.Actions.Add, MyApp.Actions.Search])

      # With prefix
      tools = Jido.AI.ToolAdapter.from_actions(actions, prefix: "calc_")
      # Tool names become "calc_add", "calc_search", etc.

      # With filter
      tools = Jido.AI.ToolAdapter.from_actions(actions,
        filter: fn mod -> mod.category() == :math end
      )
  """
  @spec from_actions([module()], keyword()) :: [ReqLLM.Tool.t()]
  def from_actions(action_modules, opts \\ [])

  def from_actions(action_modules, opts) when is_list(action_modules) do
    action_modules
    |> to_manifests(opts)
    |> from_manifests()
  end

  @doc """
  Converts a single Jido.Action module into a ReqLLM.Tool struct.

  ## Arguments

    * `action_module` - A module implementing the `Jido.Action` behaviour
    * `opts` - Optional keyword list of options

  ## Options

    * `:prefix` - String prefix to add to the tool name (e.g., `"myapp_"`)
    * `:strict` - Whether to enable strict mode on the tool. When not set,
      auto-detects based on the action's `strict?/0` callback (defaults to `false`).

  ## Returns

    A `ReqLLM.Tool` struct

  ## Example

      tool = Jido.AI.ToolAdapter.from_action(MyApp.Actions.Calculator, prefix: "v2_")
      # => %ReqLLM.Tool{name: "v2_calculator", ...}
  """
  @spec from_action(module() | ToolManifest.t(), keyword()) :: ReqLLM.Tool.t()
  def from_action(action_module, opts \\ [])

  def from_action(%ToolManifest{} = manifest, _opts), do: from_manifest(manifest)

  def from_action(action_module, opts) when is_atom(action_module) do
    action_module
    |> to_manifest(opts)
    |> from_manifest()
  end

  @doc """
  Converts a single action module into a backend-neutral tool manifest.
  """
  @spec to_manifest(module() | ToolManifest.t(), keyword()) :: ToolManifest.t()
  def to_manifest(action_module, opts \\ [])

  def to_manifest(%ToolManifest{} = manifest, _opts), do: manifest
  def to_manifest(action_module, opts) when is_atom(action_module), do: ToolManifest.from_action(action_module, opts)

  @doc """
  Converts modules or existing manifests into canonical tool manifests.
  """
  @spec to_manifests(nil | map() | [module() | ToolManifest.t()] | module() | ToolManifest.t(), keyword()) :: [ToolManifest.t()]
  def to_manifests(tools, opts \\ [])

  def to_manifests(nil, _opts), do: []

  def to_manifests(%{} = tools, opts) do
    tools
    |> Map.values()
    |> to_manifests(opts)
  end

  def to_manifests(tools, _opts) when is_list(tools) and tools == [], do: []

  def to_manifests(tools, opts) when is_list(tools) do
    cond do
      Enum.all?(tools, &match?(%ToolManifest{}, &1)) ->
        ensure_unique_manifest_names(tools)

      true ->
        ToolManifest.from_actions(tools, opts)
    end
  end

  def to_manifests(%ToolManifest{} = manifest, _opts), do: [manifest]
  def to_manifests(action_module, opts) when is_atom(action_module), do: [to_manifest(action_module, opts)]
  def to_manifests(_tools, _opts), do: []

  @doc """
  Converts canonical tool manifests into ReqLLM.Tool structs.
  """
  @spec from_manifests([ToolManifest.t()]) :: [ReqLLM.Tool.t()]
  def from_manifests(manifests) when is_list(manifests) do
    manifests
    |> ensure_unique_manifest_names()
    |> Enum.map(&from_manifest/1)
  end

  @doc """
  Converts one canonical tool manifest into a ReqLLM.Tool struct.
  """
  @spec from_manifest(ToolManifest.t()) :: ReqLLM.Tool.t()
  def from_manifest(%ToolManifest{} = manifest) do
    ReqLLM.Tool.new!(
      name: manifest.name,
      description: manifest.description,
      parameter_schema: manifest.parameter_schema,
      callback: &noop_callback/1,
      strict: manifest.strict
    )
  end

  @doc """
  Normalizes tool input into an action lookup map (`%{name => module}`).

  Accepts any of the common tool container shapes used by actions/skills:

  - `nil` -> `%{}`
  - `%{"tool_name" => MyAction}` -> unchanged
  - `%{tool_name: MyAction}` -> `%{"tool_name" => MyAction}` when values are modules
  - `[MyAction, OtherAction]` -> `%{"my_action" => MyAction, "other_action" => OtherAction}`
  - `MyAction` -> `%{"my_action" => MyAction}`
  """
  @spec to_action_map(nil | map() | [module() | ToolManifest.t()] | module() | ToolManifest.t()) :: %{String.t() => module()}
  def to_action_map(nil), do: %{}

  def to_action_map(%{} = tools) do
    cond do
      Enum.all?(tools, fn {name, mod} -> is_binary(name) and valid_action_module?(mod) end) ->
        tools

      Enum.all?(tools, fn {name, manifest} -> is_binary(name) and match?(%ToolManifest{}, manifest) end) ->
        Map.new(tools, fn {name, manifest} -> {name, manifest.module} end)

      true ->
        tools
        |> Map.values()
        |> to_action_map()
    end
  end

  def to_action_map(modules) when is_list(modules) do
    modules
    |> Enum.reduce(%{}, fn
      %ToolManifest{name: name, module: module}, acc ->
        Map.put(acc, name, module)

      module, acc ->
        if is_atom(module) and valid_action_module?(module) do
          Map.put(acc, module.name(), module)
        else
          acc
        end
    end)
  end

  def to_action_map(%ToolManifest{name: name, module: module}), do: %{name => module}

  def to_action_map(module) when is_atom(module) do
    if valid_action_module?(module) do
      %{module.name() => module}
    else
      %{}
    end
  end

  def to_action_map(_), do: %{}

  @doc """
  Looks up an action module by tool name from a list of action modules.

  Useful for finding which action module corresponds to a tool name returned
  by an LLM.

  ## Arguments

    * `tool_name` - The name of the tool to look up
    * `action_modules` - List of action modules to search

  ## Returns

    * `{:ok, module}` - If found
    * `{:error, :not_found}` - If no action module has that tool name

  ## Example

      {:ok, module} = ToolAdapter.lookup_action("calculator", [Calculator, Search])
      # => {:ok, Calculator}

      {:error, :not_found} = ToolAdapter.lookup_action("unknown", [Calculator])
      # => {:error, :not_found}
  """
  @spec lookup_action(String.t(), [module()], keyword()) :: {:ok, module()} | {:error, :not_found}
  def lookup_action(tool_name, action_modules, opts \\ [])

  def lookup_action(tool_name, action_modules, opts) when is_binary(tool_name) and is_list(action_modules) do
    prefix = Keyword.get(opts, :prefix)

    case Enum.find(action_modules, fn mod -> apply_prefix(mod.name(), prefix) == tool_name end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Validates that all modules in the list implement the Jido.Action behaviour.

  Returns `:ok` if all modules are valid, or `{:error, {:invalid_action, module, reason}}`
  for the first invalid module found.

  ## Example

      :ok = ToolAdapter.validate_actions([Calculator, Search])
      {:error, {:invalid_action, BadModule, :missing_name}} = ToolAdapter.validate_actions([BadModule])
  """
  @spec validate_actions([module()]) :: :ok | {:error, {:invalid_action, module(), atom()}}
  def validate_actions(action_modules) when is_list(action_modules) do
    Enum.reduce_while(action_modules, :ok, fn module, :ok ->
      case validate_action_module(module) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_action, module, reason}}}
      end
    end)
  end

  defp validate_action_module(module) do
    cond do
      not Code.ensure_loaded?(module) -> {:error, :not_loaded}
      not function_exported?(module, :name, 0) -> {:error, :missing_name}
      not function_exported?(module, :description, 0) -> {:error, :missing_description}
      not function_exported?(module, :schema, 0) -> {:error, :missing_schema}
      true -> :ok
    end
  end

  defp valid_action_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :name, 0)
  end

  defp valid_action_module?(_), do: false

  defp noop_callback(_args), do: {:ok, %{}}

  defp ensure_unique_manifest_names(manifests) do
    names = Enum.map(manifests, & &1.name)
    duplicates = names -- Enum.uniq(names)

    if duplicates != [] do
      raise ArgumentError,
            "Duplicate tool names detected: #{inspect(Enum.uniq(duplicates))}. " <>
              "Each action must have a unique name."
    end

    manifests
  end

  defp apply_prefix(name, nil), do: name
  defp apply_prefix(name, prefix) when is_binary(prefix), do: prefix <> name
end
