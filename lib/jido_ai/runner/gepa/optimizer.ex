defmodule Jido.AI.Runner.GEPA.Optimizer do
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

  alias Jido.AI.Runner.GEPA.Population

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
    field(:population, Population.t() | nil, default: nil)
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
    Logger.info(
      "Initializing GEPA Optimizer (population_size: #{config.population_size}, max_generations: #{config.max_generations}, evaluation_budget: #{config.evaluation_budget})"
    )

    state = %State{
      config: config,
      population: nil,
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
    Logger.debug(
      "Initializing population from seed prompts (seed_count: #{length(state.config.seed_prompts)})"
    )

    {:ok, population} = initialize_population(state.config)
    stats = Population.statistics(population)

    new_state = %{state | population: population, status: :ready}

    Logger.info(
      "GEPA Optimizer initialized and ready (population_size: #{stats.size}, status: #{new_state.status})"
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:optimize, _from, %State{status: status} = state)
      when status not in [:ready, :paused] do
    {:reply, {:error, {:invalid_status, status}}, state}
  end

  def handle_call(:optimize, _from, %State{} = state) do
    Logger.info(
      "Starting optimization cycle (generation: #{state.generation}, evaluations_remaining: #{state.config.evaluation_budget - state.evaluations_used})"
    )

    # Execute optimization loop (placeholder - will be implemented in later tasks)
    result = execute_optimization_loop(state)

    {:reply, {:ok, result}, %{state | status: :completed}}
  end

  @impl true
  def handle_call({:get_best_prompts, limit}, _from, %State{} = state) do
    best_candidates =
      if state.population do
        Population.get_best(state.population, limit: limit)
      else
        []
      end

    # Convert Population.Candidate structs to simple maps for API compatibility
    best_prompts =
      Enum.map(best_candidates, fn candidate ->
        %{
          prompt: candidate.prompt,
          fitness: candidate.fitness,
          generation: candidate.generation,
          metadata: candidate.metadata
        }
      end)

    {:reply, {:ok, best_prompts}, state}
  end

  @impl true
  def handle_call(:status, _from, %State{} = state) do
    population_stats =
      if state.population do
        Population.statistics(state.population)
      else
        %{size: 0, best_fitness: 0.0}
      end

    status_info = %{
      status: state.status,
      generation: state.generation,
      evaluations_used: state.evaluations_used,
      evaluations_remaining: state.config.evaluation_budget - state.evaluations_used,
      best_fitness: population_stats.best_fitness,
      population_size: population_stats.size,
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
  @spec initialize_population(Config.t()) :: {:ok, Population.t()} | {:error, term()}
  defp initialize_population(%Config{} = config) do
    # Create new empty population
    {:ok, population} = Population.new(size: config.population_size, generation: 0)

    # Generate initial candidates
    candidates =
      if length(config.seed_prompts) > 0 do
        # Use seed prompts as initial population
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
                seed_index: index
              }
            }
          end)

        # If we need more candidates, generate variations
        needed = config.population_size - length(seed_candidates)

        if needed > 0 do
          variations = generate_initial_variations(seed_candidates, needed)
          seed_candidates ++ variations
        else
          seed_candidates
        end
      else
        # Generate default baseline prompts
        generate_default_prompts(config.population_size)
      end

    # Add all candidates to population
    population =
      Enum.reduce(candidates, population, fn candidate, pop ->
        case Population.add_candidate(pop, candidate) do
          {:ok, updated_pop} -> updated_pop
          {:error, _reason} -> pop
        end
      end)

    Logger.debug(
      "Population initialized (total: #{population.size}, candidates: #{length(Population.get_all(population))})"
    )

    {:ok, population}
  end

  @doc false
  @spec generate_initial_variations(list(map()), pos_integer()) :: list(map())
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
          variation_index: index
        }
      }
    end)
  end

  @doc false
  @spec generate_default_prompts(pos_integer()) :: list(map())
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
          index: i
        }
      }
    end
  end

  @doc false
  @spec execute_optimization_loop(State.t()) :: optimization_result()
  defp execute_optimization_loop(%State{} = state) do
    Logger.info(
      "Starting evolution cycle coordination (max_generations: #{state.config.max_generations}, evaluation_budget: #{state.config.evaluation_budget})"
    )

    updated_state = %{state | status: :running}

    # Run evolution cycles until termination condition met
    final_state = run_evolution_cycles(updated_state)

    # Prepare final result
    prepare_optimization_result(final_state)
  end

  @doc false
  @spec run_evolution_cycles(State.t()) :: State.t()
  defp run_evolution_cycles(%State{} = state) do
    if should_stop?(state) do
      # Check if we should stop
      Logger.info("Evolution cycle terminated", reason: get_stop_reason(state))
      state
    else
      # Continue to next generation
      Logger.info("Starting generation #{state.generation + 1}")

      # Execute one complete generation cycle
      case execute_generation(state) do
        {:ok, new_state} ->
          # Recursively continue to next generation
          run_evolution_cycles(new_state)

        {:error, reason} ->
          Logger.error(
            "Generation failed (reason: #{inspect(reason)}, generation: #{state.generation})"
          )

          %{state | status: :failed}
      end
    end
  end

  @doc false
  @spec execute_generation(State.t()) :: {:ok, State.t()} | {:error, term()}
  defp execute_generation(%State{} = state) do
    # Phase 1: Evaluation - evaluate all candidates in population
    Logger.debug("Phase 1: Evaluating population (generation: #{state.generation + 1})")
    {evaluation_results, evals_used} = evaluate_population(state)

    # Update state with evaluation results
    state_after_eval = update_population_fitness(state, evaluation_results, evals_used)

    # Phase 2: Reflection - analyze results (placeholder for Section 1.3)
    Logger.debug("Phase 2: Reflection (placeholder) (generation: #{state.generation + 1})")
    reflection_insights = perform_reflection(state_after_eval)

    # Phase 3: Mutation - generate new candidates (placeholder for Section 1.4)
    Logger.debug("Phase 3: Mutation (placeholder) (generation: #{state.generation + 1})")
    offspring = generate_offspring(state_after_eval, reflection_insights)

    # Phase 4: Selection - select next generation
    Logger.debug("Phase 4: Selection (generation: #{state.generation + 1})")
    next_population = perform_selection(state_after_eval, offspring)

    # Phase 5: Progress tracking - record generation metrics
    Logger.debug("Phase 5: Recording generation metrics (generation: #{state.generation + 1})")
    final_state = record_generation_metrics(state_after_eval, next_population)

    Logger.info(
      "Generation #{final_state.generation} complete (best_fitness: #{final_state.best_fitness}, evaluations_used: #{final_state.evaluations_used})"
    )

    {:ok, final_state}
  rescue
    e ->
      Logger.error(
        "Error in generation execution (error: #{Exception.message(e)}, stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)})"
      )

      {:error, e}
  end

  # Phase 1: Evaluation
  @doc false
  @spec evaluate_population(State.t()) :: {list(map()), non_neg_integer()}
  defp evaluate_population(%State{} = state) do
    candidates = Population.get_all(state.population)
    unevaluated = Enum.filter(candidates, fn c -> is_nil(c.fitness) end)

    # For now, use simple mock evaluation
    # Real evaluation will use Scheduler (Task 1.1.3) and evaluation system (Section 1.2)
    results =
      Enum.map(unevaluated, fn candidate ->
        # Mock fitness: random score with some correlation to prompt length
        fitness = mock_evaluate_prompt(candidate.prompt)
        %{id: candidate.id, fitness: fitness}
      end)

    evaluations_count = length(results)
    Logger.debug("Evaluated #{evaluations_count} candidates")

    {results, evaluations_count}
  end

  @doc false
  @spec mock_evaluate_prompt(String.t()) :: float()
  defp mock_evaluate_prompt(prompt) do
    # Simple mock: score based on prompt characteristics
    # Real implementation will use actual task evaluation
    base_score = 0.5
    length_factor = min(String.length(prompt) / 200.0, 0.3)
    randomness = :rand.uniform() * 0.2

    min(base_score + length_factor + randomness, 1.0)
  end

  @doc false
  @spec update_population_fitness(State.t(), list(map()), non_neg_integer()) :: State.t()
  defp update_population_fitness(%State{} = state, results, evals_used) do
    # Update fitness for each evaluated candidate
    population =
      Enum.reduce(results, state.population, fn result, pop ->
        case Population.update_fitness(pop, result.id, result.fitness) do
          {:ok, updated_pop} -> updated_pop
          {:error, _} -> pop
        end
      end)

    stats = Population.statistics(population)

    %{
      state
      | population: population,
        evaluations_used: state.evaluations_used + evals_used,
        best_fitness: stats.best_fitness
    }
  end

  # Phase 2: Reflection (placeholder)
  @doc false
  @spec perform_reflection(State.t()) :: map()
  defp perform_reflection(%State{} = _state) do
    # Placeholder for LLM-guided reflection (Section 1.3)
    # Returns mock insights for now
    %{
      insights: [],
      suggestions: [],
      failure_patterns: []
    }
  end

  # Phase 3: Mutation (placeholder)
  @doc false
  @spec generate_offspring(State.t(), map()) :: list(map())
  defp generate_offspring(%State{} = state, _insights) do
    # Placeholder for mutation operators (Section 1.4)
    # Generate simple variations of best candidates for now
    best_candidates = Population.get_best(state.population, limit: 3)

    offspring =
      Enum.flat_map(best_candidates, fn parent ->
        [
          %{
            prompt: "#{parent.prompt} (variation)",
            fitness: nil,
            generation: state.generation + 1,
            parent_ids: [parent.id],
            metadata: %{source: :mutation, parent: parent.id}
          }
        ]
      end)

    Logger.debug("Generated #{length(offspring)} offspring")
    offspring
  end

  # Phase 4: Selection
  @doc false
  @spec perform_selection(State.t(), list(map())) :: Population.t()
  defp perform_selection(%State{} = state, offspring) do
    # Simple fitness-based selection (elitism + offspring)
    # More sophisticated selection (Pareto, tournament) in Stage 2

    # Get all evaluated candidates
    all_candidates = Population.get_all(state.population)
    evaluated = Enum.filter(all_candidates, fn c -> not is_nil(c.fitness) end)

    # Sort by fitness and take top performers (elitism)
    elite_count = div(state.config.population_size, 2)
    elites = Enum.take(Enum.sort_by(evaluated, & &1.fitness, :desc), elite_count)

    Logger.debug("Selected #{length(elites)} elites for next generation")

    # Create new population
    {:ok, next_population} =
      Population.new(
        size: state.config.population_size,
        generation: state.generation + 1
      )

    # Add elites
    next_population =
      Enum.reduce(elites, next_population, fn candidate, pop ->
        case Population.add_candidate(pop, Map.from_struct(candidate)) do
          {:ok, updated_pop} -> updated_pop
          {:error, _} -> pop
        end
      end)

    # Add offspring to fill population
    next_population =
      Enum.reduce(offspring, next_population, fn candidate, pop ->
        case Population.add_candidate(pop, candidate) do
          {:ok, updated_pop} -> updated_pop
          {:error, _} -> pop
        end
      end)

    next_population
  end

  # Phase 5: Progress Tracking
  @doc false
  @spec record_generation_metrics(State.t(), Population.t()) :: State.t()
  defp record_generation_metrics(%State{} = state, next_population) do
    stats = Population.statistics(next_population)

    generation_metrics = %{
      generation: state.generation + 1,
      best_fitness: stats.best_fitness,
      avg_fitness: stats.avg_fitness,
      diversity: stats.diversity,
      evaluations_used: state.evaluations_used,
      timestamp: System.monotonic_time(:millisecond)
    }

    %{
      state
      | population: next_population,
        generation: state.generation + 1,
        history: [generation_metrics | state.history],
        best_fitness: stats.best_fitness
    }
  end

  # Early Stopping / Convergence Detection
  @doc false
  @spec should_stop?(State.t()) :: boolean()
  defp should_stop?(%State{} = state) do
    cond do
      # Check generation limit
      state.generation >= state.config.max_generations ->
        true

      # Check evaluation budget
      state.evaluations_used >= state.config.evaluation_budget ->
        true

      # Check convergence (fitness plateau)
      converged?(state) ->
        true

      # Continue
      true ->
        false
    end
  end

  @doc false
  @spec converged?(State.t()) :: boolean()
  defp converged?(%State{} = state) do
    # Need at least 3 generations to detect plateau
    if length(state.history) < 3 do
      false
    else
      # Check if best fitness hasn't improved in last 3 generations
      recent_history = Enum.take(state.history, 3)
      fitnesses = Enum.map(recent_history, & &1.best_fitness)

      # Calculate fitness variance
      mean = Enum.sum(fitnesses) / length(fitnesses)

      variance =
        Enum.reduce(fitnesses, 0.0, fn f, acc ->
          acc + :math.pow(f - mean, 2)
        end) / length(fitnesses)

      # Converged if variance is very small (< 0.001)
      variance < 0.001
    end
  end

  @doc false
  @spec get_stop_reason(State.t()) :: atom()
  defp get_stop_reason(%State{} = state) do
    cond do
      state.generation >= state.config.max_generations ->
        :max_generations_reached

      state.evaluations_used >= state.config.evaluation_budget ->
        :budget_exhausted

      converged?(state) ->
        :converged

      true ->
        :unknown
    end
  end

  @doc false
  @spec prepare_optimization_result(State.t()) :: optimization_result()
  defp prepare_optimization_result(%State{} = state) do
    duration_ms = System.monotonic_time(:millisecond) - state.started_at

    best_candidates =
      if state.population do
        Population.get_best(state.population, limit: 5)
      else
        []
      end

    # Convert to simple maps for API compatibility
    best_prompts =
      Enum.map(best_candidates, fn candidate ->
        %{
          prompt: candidate.prompt,
          fitness: candidate.fitness,
          generation: candidate.generation,
          metadata: candidate.metadata
        }
      end)

    %{
      best_prompts: best_prompts,
      final_generation: state.generation,
      total_evaluations: state.evaluations_used,
      history: Enum.reverse(state.history),
      duration_ms: duration_ms,
      stop_reason: get_stop_reason(state)
    }
  end
end
