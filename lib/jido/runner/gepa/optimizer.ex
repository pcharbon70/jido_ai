defmodule Jido.Runner.GEPA.Optimizer do
  @moduledoc """
  GEPA (Genetic-Pareto) Optimizer Agent implementing evolutionary prompt optimization.

  This GenServer manages the core evolutionary optimization loop for prompt improvement,
  maintaining a population of prompt candidates and orchestrating the reflection-mutation-selection
  cycle. The optimizer leverages Elixir's OTP concurrency to parallelize prompt evaluations
  across spawned Jido agents.

  ## Key Concepts

  GEPA treats prompt optimization as an evolutionary search problem where:
  - The LLM serves as a reflective coach analyzing execution failures
  - Prompt candidates evolve through targeted mutations based on LLM feedback
  - A diverse population is maintained along a Pareto frontier (multi-objective)
  - Sample efficiency is achieved through language-guided evolution

  ## Architecture

  The optimizer coordinates four main phases:
  1. **Evaluation**: Parallel execution of prompt variants using Jido agents
  2. **Reflection**: LLM analysis of execution trajectories to identify improvements
  3. **Mutation**: Targeted prompt modifications based on reflection insights
  4. **Selection**: Pareto-based selection maintaining diverse high-performers

  ## Configuration

  - `:population_size` - Number of prompt candidates in population (default: 10)
  - `:max_generations` - Maximum evolution cycles (default: 20)
  - `:evaluation_budget` - Maximum total evaluations (default: 200)
  - `:seed_prompts` - Initial prompt population (default: [])
  - `:task` - Task definition for evaluation (required)
  - `:parallelism` - Concurrent evaluation limit (default: 5)

  ## Usage

      # Start optimizer with configuration
      {:ok, pid} = Optimizer.start_link(
        population_size: 10,
        max_generations: 20,
        evaluation_budget: 200,
        seed_prompts: ["Solve this step by step..."],
        task: %{type: :reasoning, benchmark: "GSM8K"}
      )

      # Run optimization cycle
      {:ok, result} = Optimizer.optimize(pid)

      # Get current best prompts
      {:ok, prompts} = Optimizer.get_best_prompts(pid, limit: 5)

      # Get optimization status
      {:ok, status} = Optimizer.status(pid)

  ## State Structure

  The optimizer maintains:
  - **Population**: Current prompt candidates with fitness scores
  - **Generation Counter**: Current evolution cycle number
  - **Optimization History**: Performance metrics across generations
  - **Evaluation Budget Tracking**: Remaining evaluation capacity
  - **Configuration**: Runtime parameters for optimization

  ## Research Background

  GEPA achieves 10-19% performance improvements over baselines while using
  up to 35× fewer evaluations than RL methods by leveraging language feedback
  for targeted prompt evolution.

  **Reference**: Agrawal et al., "GEPA: Reflective Prompt Evolution Can Outperform
  Reinforcement Learning" (arXiv:2507.19457)
  """

  use GenServer
  use TypedStruct
  require Logger

  # Type definitions

  typedstruct module: Config do
    @moduledoc """
    Configuration schema for GEPA Optimizer.

    Defines all configurable parameters controlling optimization behavior.
    """

    field(:population_size, pos_integer(), default: 10)
    field(:max_generations, pos_integer(), default: 20)
    field(:evaluation_budget, pos_integer(), default: 200)
    field(:seed_prompts, list(String.t()), default: [])
    field(:task, map(), enforce: true)
    field(:parallelism, pos_integer(), default: 5)
    field(:name, atom(), default: nil)
  end

  typedstruct module: State do
    @moduledoc """
    Internal state structure for GEPA Optimizer GenServer.

    Maintains population, generation tracking, and optimization history.
    """

    field(:config, Config.t(), enforce: true)
    field(:population, list(map()), default: [])
    field(:generation, non_neg_integer(), default: 0)
    field(:evaluations_used, non_neg_integer(), default: 0)
    field(:history, list(map()), default: [])
    field(:status, atom(), default: :initializing)
    field(:best_fitness, float(), default: 0.0)
    field(:started_at, integer(), default: nil)
  end

  @type prompt_candidate :: %{
          prompt: String.t(),
          fitness: float() | nil,
          generation: non_neg_integer(),
          metadata: map()
        }

  @type optimization_result :: %{
          best_prompts: list(prompt_candidate()),
          final_generation: non_neg_integer(),
          total_evaluations: non_neg_integer(),
          history: list(map()),
          duration_ms: non_neg_integer()
        }

  # Client API

  @doc """
  Starts the GEPA Optimizer GenServer.

  ## Options

  See module documentation for configuration details.

  ## Examples

      {:ok, pid} = Optimizer.start_link(
        population_size: 10,
        max_generations: 20,
        task: %{type: :reasoning}
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    config = build_config!(opts)
    name = Keyword.get(opts, :name)

    server_opts =
      if name do
        [name: name]
      else
        []
      end

    GenServer.start_link(__MODULE__, config, server_opts)
  end

  @doc """
  Runs the complete optimization cycle.

  Executes evolutionary optimization until convergence, budget exhaustion,
  or maximum generations reached.

  ## Examples

      {:ok, result} = Optimizer.optimize(pid)
  """
  @spec optimize(GenServer.server()) :: {:ok, optimization_result()} | {:error, term()}
  def optimize(server) do
    GenServer.call(server, :optimize, :infinity)
  end

  @doc """
  Retrieves the current best prompts from the population.

  ## Options

  - `:limit` - Maximum number of prompts to return (default: 5)

  ## Examples

      {:ok, prompts} = Optimizer.get_best_prompts(pid, limit: 3)
  """
  @spec get_best_prompts(GenServer.server(), keyword()) :: {:ok, list(prompt_candidate())}
  def get_best_prompts(server, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    GenServer.call(server, {:get_best_prompts, limit})
  end

  @doc """
  Returns the current optimization status and metrics.

  ## Examples

      {:ok, status} = Optimizer.status(pid)
      # => %{
      #   status: :running,
      #   generation: 5,
      #   evaluations_used: 50,
      #   best_fitness: 0.85,
      #   population_size: 10
      # }
  """
  @spec status(GenServer.server()) :: {:ok, map()}
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Stops the optimizer gracefully.

  ## Examples

      :ok = Optimizer.stop(pid)
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # Server Callbacks

  @impl true
  @spec init(Config.t()) :: {:ok, State.t()}
  def init(%Config{} = config) do
    Logger.info("Initializing GEPA Optimizer",
      population_size: config.population_size,
      max_generations: config.max_generations,
      evaluation_budget: config.evaluation_budget
    )

    state = %State{
      config: config,
      population: [],
      generation: 0,
      evaluations_used: 0,
      history: [],
      status: :initializing,
      best_fitness: 0.0,
      started_at: System.monotonic_time(:millisecond)
    }

    # Initialize population from seed prompts
    {:ok, state, {:continue, :initialize_population}}
  end

  @impl true
  def handle_continue(:initialize_population, %State{} = state) do
    Logger.debug("Initializing population from seed prompts",
      seed_count: length(state.config.seed_prompts)
    )

    population = initialize_population(state.config)

    new_state = %{state | population: population, status: :ready}

    Logger.info("GEPA Optimizer initialized and ready",
      population_size: length(population),
      status: new_state.status
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:optimize, _from, %State{status: status} = state)
      when status not in [:ready, :paused] do
    {:reply, {:error, {:invalid_status, status}}, state}
  end

  def handle_call(:optimize, _from, %State{} = state) do
    Logger.info("Starting optimization cycle",
      generation: state.generation,
      evaluations_remaining: state.config.evaluation_budget - state.evaluations_used
    )

    # Execute optimization loop (placeholder - will be implemented in later tasks)
    result = execute_optimization_loop(state)

    {:reply, {:ok, result}, %{state | status: :completed}}
  end

  @impl true
  def handle_call({:get_best_prompts, limit}, _from, %State{} = state) do
    best_prompts =
      state.population
      |> Enum.filter(&(&1.fitness != nil))
      |> Enum.sort_by(& &1.fitness, :desc)
      |> Enum.take(limit)

    {:reply, {:ok, best_prompts}, state}
  end

  @impl true
  def handle_call(:status, _from, %State{} = state) do
    status_info = %{
      status: state.status,
      generation: state.generation,
      evaluations_used: state.evaluations_used,
      evaluations_remaining: state.config.evaluation_budget - state.evaluations_used,
      best_fitness: state.best_fitness,
      population_size: length(state.population),
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at
    }

    {:reply, {:ok, status_info}, state}
  end

  # Private Functions

  @doc false
  @spec build_config!(keyword()) :: Config.t()
  defp build_config!(opts) do
    unless Keyword.has_key?(opts, :task) do
      raise ArgumentError, "task configuration is required"
    end

    %Config{
      population_size: Keyword.get(opts, :population_size, 10),
      max_generations: Keyword.get(opts, :max_generations, 20),
      evaluation_budget: Keyword.get(opts, :evaluation_budget, 200),
      seed_prompts: Keyword.get(opts, :seed_prompts, []),
      task: Keyword.fetch!(opts, :task),
      parallelism: Keyword.get(opts, :parallelism, 5),
      name: Keyword.get(opts, :name)
    }
  end

  @doc false
  @spec initialize_population(Config.t()) :: list(prompt_candidate())
  defp initialize_population(%Config{} = config) do
    # Generate initial population from seed prompts
    seed_candidates =
      config.seed_prompts
      |> Enum.with_index()
      |> Enum.map(fn {prompt, index} ->
        %{
          prompt: prompt,
          fitness: nil,
          generation: 0,
          metadata: %{
            source: :seed,
            seed_index: index,
            created_at: System.monotonic_time(:millisecond)
          }
        }
      end)

    # If we have fewer seed prompts than population size, generate variations
    needed = config.population_size - length(seed_candidates)

    additional_candidates =
      if needed > 0 and length(seed_candidates) > 0 do
        generate_initial_variations(seed_candidates, needed)
      else
        []
      end

    # If no seed prompts provided, generate default baseline prompts
    final_population =
      if length(seed_candidates) == 0 do
        generate_default_prompts(config.population_size)
      else
        seed_candidates ++ additional_candidates
      end

    Logger.debug("Population initialized",
      total: length(final_population),
      from_seeds: length(seed_candidates),
      generated: length(additional_candidates)
    )

    final_population
  end

  @doc false
  @spec generate_initial_variations(list(prompt_candidate()), pos_integer()) ::
          list(prompt_candidate())
  defp generate_initial_variations(seed_candidates, count) do
    # Simple variation strategy: duplicate seeds with minor variations
    # More sophisticated variation will be implemented in mutation tasks
    seed_candidates
    |> Stream.cycle()
    |> Stream.take(count)
    |> Stream.with_index()
    |> Enum.map(fn {candidate, index} ->
      %{
        prompt: candidate.prompt,
        fitness: nil,
        generation: 0,
        metadata: %{
          source: :variation,
          parent_seed: candidate.metadata.seed_index,
          variation_index: index,
          created_at: System.monotonic_time(:millisecond)
        }
      }
    end)
  end

  @doc false
  @spec generate_default_prompts(pos_integer()) :: list(prompt_candidate())
  defp generate_default_prompts(count) do
    # Generate simple baseline prompts when no seeds provided
    default_prompt = "Let's approach this problem step by step."

    for i <- 0..(count - 1) do
      %{
        prompt: default_prompt,
        fitness: nil,
        generation: 0,
        metadata: %{
          source: :default,
          index: i,
          created_at: System.monotonic_time(:millisecond)
        }
      }
    end
  end

  @doc false
  @spec execute_optimization_loop(State.t()) :: optimization_result()
  defp execute_optimization_loop(%State{} = state) do
    # Placeholder for optimization loop
    # This will be implemented in subsequent tasks (1.1.2, 1.1.3, 1.1.4)
    Logger.info("Optimization loop placeholder - to be implemented in Tasks 1.1.2-1.1.4")

    duration_ms = System.monotonic_time(:millisecond) - state.started_at

    %{
      best_prompts: Enum.take(state.population, 5),
      final_generation: state.generation,
      total_evaluations: state.evaluations_used,
      history: state.history,
      duration_ms: duration_ms
    }
  end
end
