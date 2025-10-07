defmodule Examples.FullLifecycleHookAgent do
  @moduledoc """
  Example agent demonstrating complete Chain-of-Thought lifecycle hook integration.

  This agent uses all three CoT lifecycle hooks:
  - `on_before_plan/3` - Strategic planning before queuing
  - `on_before_run/1` - Execution analysis before running
  - `on_after_run/3` - Validation after execution

  ## Usage

      # Create agent
      agent = Examples.FullLifecycleHookAgent.new()

      # Enable all CoT hooks (enabled by default)
      agent = agent
        |> Jido.Agent.set(:enable_planning_cot, true)
        |> Jido.Agent.set(:enable_execution_cot, true)

      # Queue some actions - planning hook analyzes
      agent = Jido.Agent.enqueue(agent, SomeAction, %{}, context: %{enable_planning_cot: true})

      # Run agent - execution hook analyzes, then executes, then validation
      {:ok, result_agent, directives} = Jido.Agent.run(agent)

      # Access planning and execution context
      {:ok, planning} = Jido.Runner.ChainOfThought.PlanningHook.get_planning_reasoning(result_agent)
      {:ok, plan} = Jido.Runner.ChainOfThought.ExecutionHook.get_execution_plan(result_agent)

  ## Features

  - Complete lifecycle CoT integration
  - Strategic planning → Execution analysis → Result validation
  - Planning context available to execution hook
  - Execution plan available to validation hook
  - Opt-in/opt-out for each hook independently
  - Graceful degradation at each stage
  """

  use Jido.Agent,
    name: "full_lifecycle_hook_agent",
    actions: [],
    schema: []

  alias Jido.Runner.ChainOfThought.{PlanningHook, ExecutionHook}

  @doc """
  Planning hook - generates strategic reasoning before instructions are queued.
  """
  @impl Jido.Agent
  def on_before_plan(agent, instructions, context) do
    PlanningHook.generate_planning_reasoning(agent, instructions, context)
  end

  @doc """
  Execution hook - analyzes pending instructions before execution.

  Has access to planning reasoning from on_before_plan for enhanced analysis.
  """
  @impl Jido.Agent
  def on_before_run(agent) do
    case ExecutionHook.generate_execution_plan(agent) do
      {:ok, updated_agent} = result ->
        # Log integration of planning and execution
        with {:ok, planning} <- PlanningHook.get_planning_reasoning(updated_agent),
             {:ok, plan} <- ExecutionHook.get_execution_plan(updated_agent) do
          require Logger

          Logger.info("""
          Lifecycle CoT Context:
            Planning Goal: #{planning.goal}
            Planning Dependencies: #{length(planning.dependencies)}
            Execution Strategy: #{plan.execution_strategy}
            Execution Steps: #{length(plan.steps)}
            Error Points: #{length(plan.error_points)}
          """)
        end

        result

      error ->
        error
    end
  end

  @doc """
  Validation hook - validates execution results against planning and execution context.

  Has access to both planning reasoning and execution plan for comprehensive validation.
  """
  @impl Jido.Agent
  def on_after_run(agent, result, unapplied_directives) do
    require Logger

    planning_result = PlanningHook.get_planning_reasoning(agent)
    execution_result = ExecutionHook.get_execution_plan(agent)

    case {planning_result, execution_result} do
      {{:ok, planning}, {:ok, plan}} ->
        Logger.info("""
        Validating execution with full CoT context:
          Planning Goal: #{planning.goal}
          Anticipated Issues: #{length(planning.potential_issues)}
          Execution Steps: #{length(plan.steps)}
          Error Points: #{length(plan.error_points)}
          Result: #{inspect(result, limit: 3)}
        """)

        # Cross-reference planning issues with execution error points
        validate_against_planning(planning, plan, result)

        {:ok, agent}

      {{:ok, planning}, {:error, _}} ->
        Logger.info("Validation with planning context only")
        {:ok, agent}

      {{:error, _}, {:ok, plan}} ->
        Logger.info("Validation with execution plan only")
        {:ok, agent}

      _ ->
        Logger.debug("Validation without CoT context")
        {:ok, agent}
    end
  end

  # Private validation logic
  defp validate_against_planning(planning, plan, result) do
    # Example: Check if anticipated issues occurred
    for issue <- planning.potential_issues do
      # Check against execution error points
      matching_errors = Enum.filter(plan.error_points, fn ep ->
        String.contains?(String.downcase(ep.description), String.downcase(issue))
      end)

      if length(matching_errors) > 0 do
        require Logger
        Logger.debug("Anticipated issue '#{issue}' identified in execution plan")
      end
    end

    :ok
  end
end
