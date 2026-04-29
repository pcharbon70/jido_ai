defmodule Jido.AI.Actions.Planning.Decompose do
  @moduledoc """
  A Jido.Action for breaking down complex goals into hierarchical sub-goals.

  This action uses ReqLLM with a specialized system prompt for goal decomposition,
  creating hierarchical structures that break complex goals into manageable pieces.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:planning`) or direct spec
  * `goal` (required) - The goal to decompose
  * `max_depth` (optional) - Maximum depth of decomposition (default: `3`)
  * `context` (optional) - Additional context about the goal
  * `max_tokens` (optional) - Maximum tokens to generate (default: `4096`)
  * `temperature` (optional) - Sampling temperature (default: `0.6`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic decomposition
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Planning.Decompose, %{
        goal: "Build a mobile app"
      })

      # With specific depth
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Planning.Decompose, %{
        goal: "Launch a startup",
        max_depth: 4
      })

      # With context
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Planning.Decompose, %{
        goal: "Organize a conference",
        context: "Technology conference with 500 attendees, limited budget"
      })
  """

  use Jido.Action,
    name: "planning_decompose",
    description: "Break down complex goals into hierarchical sub-goals",
    category: "ai",
    tags: ["planning", "decomposition", "goals"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :planning) or direct model spec string")
          |> Zoi.optional(),
        backend:
          Zoi.any(description: "Optional additive backend selector such as :req_llm or :harness")
          |> Zoi.optional(),
        goal: Zoi.string(description: "The goal to decompose"),
        max_depth: Zoi.integer(description: "Maximum depth of decomposition (1-5)") |> Zoi.default(3),
        context: Zoi.string(description: "Additional context about the goal") |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(4096),
        temperature: Zoi.float(description: "Sampling temperature") |> Zoi.default(0.6),
        workspace:
          Zoi.map(description: "Optional backend-neutral workspace context such as cwd or attachments")
          |> Zoi.optional(),
        backend_metadata:
          Zoi.map(description: "Optional backend-specific additive metadata")
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers

  @decomposition_prompt """
  You are an expert at breaking down complex goals into manageable components.

  Your task is to decompose the given goal into a hierarchical structure of sub-goals.
  Each level should break down goals into actionable pieces that are easier to accomplish.

  Structure your decomposition using the following format:

  ## Level 1: Main Goal Areas
  ### 1. [Area Name]
  - **Purpose**: [Why this area matters]
  - **Sub-goals**:
    - 1.1. [Sub-goal 1]
    - 1.2. [Sub-goal 2]

  ### 2. [Area Name]
  - **Purpose**: [Why this area matters]
  - **Sub-goals**:
    - 2.1. [Sub-goal 1]
    - 2.2. [Sub-goal 2]

  ## Level 2: Detailed Breakdown
  [For key sub-goals, break them down further with specific tasks]

  ## Dependencies
  - [Identify which sub-goals depend on others]

  ## Success Criteria
  - [How to know when each sub-goal is achieved]

  Guidelines:
  - Each sub-goal should be specific and measurable
  - Sub-goals at the same level should be roughly equal in scope
  - Identify clear dependencies between sub-goals
  - Keep the decomposition practical and actionable
  """

  @doc """
  Executes the decompose action.

  ## Returns

  * `{:ok, result}` - Successful response with `decomposition`, `sub_goals`, `goal`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        decomposition: "The full decomposition text",
        sub_goals: ["Sub-goal 1", "Sub-goal 2", ...],
        goal: "The original goal",
        depth: 3,
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{...}
      }
  """
  @impl Jido.Action
  def run(params, context) do
    params = apply_context_defaults(params, context)

    with {:ok, result} <-
           Helpers.generate_backend_result(params, %{
             default_model: :planning,
             operation: :text,
             prompt: build_decompose_user_prompt(params),
             system_prompt: @decomposition_prompt
           }) do
      {:ok, format_result(result, params[:goal], clamp_depth(params[:max_depth] || 3))}
    end
  end

  # Private Functions

  defp build_decompose_user_prompt(params) do
    base = "Goal to decompose: #{params[:goal]}"

    base =
      case params[:context] do
        nil ->
          base

        context when is_binary(context) ->
          base <> "\n\nContext:\n" <> context
      end

    max_depth = clamp_depth(params[:max_depth] || 3)
    base <> "\n\nPlease decompose this goal to a maximum depth of #{max_depth} levels."
  end

  defp clamp_depth(depth) when is_integer(depth), do: max(1, min(depth, 5))
  defp clamp_depth(_), do: 3

  defp format_result(result, goal, depth) do
    decomposition_text = result.text

    %{
      decomposition: decomposition_text,
      sub_goals: extract_sub_goals(decomposition_text),
      goal: goal,
      depth: depth,
      model: result.model,
      usage: result.usage || Helpers.extract_usage(%{})
    }
  end

  defp extract_sub_goals(text) do
    # Extract sub-goals in format like "1.1. [Sub-goal]"
    Regex.scan(~r/^\d+\.\d+\.\s+(.+?)$/m, text)
    |> Enum.map(fn [_, sub_goal] -> String.trim(sub_goal) end)
    |> Enum.filter(fn s -> String.length(s) > 0 end)
  end

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)

    model_default =
      first_present([
        context[:default_model],
        context[:model],
        plugin_default(context, :default_model)
      ])

    max_depth_default =
      first_present([
        context[:default_max_depth],
        plugin_default(context, :default_max_depth)
      ])

    max_tokens_default =
      first_present([
        context[:default_max_tokens],
        plugin_default(context, :default_max_tokens)
      ])

    temperature_default =
      first_present([
        context[:default_temperature],
        plugin_default(context, :default_temperature)
      ])

    backend_default =
      first_present([
        context[:backend],
        plugin_default(context, :backend)
      ])

    workspace_default =
      merge_optional_maps(
        normalize_optional_map(plugin_default(context, :workspace)),
        normalize_optional_map(context[:workspace])
      )

    backend_metadata_default =
      merge_optional_maps(
        normalize_optional_map(plugin_default(context, :backend_metadata)),
        normalize_optional_map(context[:backend_metadata])
      )

    params
    |> put_default_param(:model, model_default, provided)
    |> put_default_param(:max_depth, max_depth_default, provided)
    |> put_default_param(:max_tokens, max_tokens_default, provided)
    |> put_default_param(:temperature, temperature_default, provided)
    |> put_default_param(:backend, backend_default, provided)
    |> merge_map_default(:workspace, workspace_default, provided)
    |> merge_map_default(:backend_metadata, backend_metadata_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp merge_map_default(params, _key, defaults, _provided) when defaults == %{}, do: params

  defp merge_map_default(params, key, defaults, provided) do
    current = normalize_optional_map(Map.get(params, key))

    merged =
      cond do
        provided == :unknown and current == %{} ->
          defaults

        provided == :unknown ->
          Map.merge(defaults, current)

        provided_param?(provided, key) ->
          Map.merge(defaults, current)

        true ->
          defaults
      end

    Map.put(params, key, merged)
  end

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp plugin_default(context, key) do
    first_present([
      get_in(context, [:plugin_state, :planning, key]),
      get_in(context, [:state, :planning, key]),
      get_in(context, [:agent, :state, :planning, key])
    ])
  end

  defp normalize_optional_map(nil), do: %{}
  defp normalize_optional_map(map) when is_map(map), do: map
  defp normalize_optional_map(map) when is_list(map), do: Map.new(map)
  defp normalize_optional_map(_), do: %{}

  defp merge_optional_maps(left, right), do: Map.merge(left, right)

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}
end
