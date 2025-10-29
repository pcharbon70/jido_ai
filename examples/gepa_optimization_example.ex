defmodule Examples.GEPAOptimizationExample do
  @moduledoc """
  Example demonstrating GEPA (Genetic-Pareto Prompt Optimization) usage.

  This example shows how to optimize prompts across multiple competing objectives:
  - Accuracy: How well the prompt performs on the task
  - Latency: How fast the prompt executes
  - Cost: How expensive the prompt is to run
  - Robustness: How consistently the prompt performs

  ## Important Note

  **This is currently a demonstration/template showing the GEPA API and structure.**
  The current implementation simulates optimization results for educational purposes.

  For actual prompt optimization, you would need to:

  1. **Integrate with real GEPA modules**: Connect to the actual Population,
     Selection, Mutation, and Crossover implementations in
     `lib/jido_ai/runner/gepa/`

  2. **Provide evaluation functions**: Implement real prompt evaluation by
     running prompts against your LLM and measuring actual accuracy, latency,
     cost, and robustness metrics

  3. **Connect to LLM providers**: Use a client library (e.g., OpenAI API,
     Anthropic API) to execute and evaluate candidate prompts

  4. **Implement mutation strategies**: Use the GEPA mutation operators
     (word swap, instruction variation, format changes) to generate prompt
     variations

  This example demonstrates the intended usage pattern and API design that the
  full GEPA implementation will provide.

  ## Basic Usage

      # Simple optimization
      {:ok, results} = Examples.GEPAOptimizationExample.optimize_prompt(
        initial_prompt: "Summarize this text concisely",
        task: :summarization,
        max_generations: 30
      )

      # Access Pareto frontier (best trade-off solutions)
      frontier = results.pareto_frontier
      IO.puts("Found #{length(frontier)} optimal solutions")

      # Select solution for your use case
      fast_solution = Examples.GEPAOptimizationExample.select_fast_solution(frontier)
      accurate_solution = Examples.GEPAOptimizationExample.select_accurate_solution(frontier)
      balanced_solution = Examples.GEPAOptimizationExample.select_balanced_solution(frontier)

  ## Advanced Usage

      # Custom objectives and convergence criteria
      {:ok, results} = Examples.GEPAOptimizationExample.optimize_with_config(
        initial_prompt: "Analyze sentiment in this review",
        task: :sentiment_analysis,
        config: %{
          population_size: 100,
          max_generations: 50,
          objectives: [:accuracy, :cost, :latency],
          convergence: %{
            patience: 10,
            min_improvement: 0.01
          }
        }
      )

  ## Features

  - Multi-objective optimization (Pareto frontier)
  - Automatic convergence detection
  - Budget management (evaluation limits)
  - Trade-off exploration and selection
  - Historical learning from past optimizations
  """

  alias Jido.AI.Runner.GEPA.{Population, Convergence}
  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Pareto.{DominanceComparator, FrontierManager}

  require Logger

  @doc """
  Basic prompt optimization with sensible defaults.

  ## Parameters

  - `initial_prompt` - Starting prompt to optimize
  - `task` - Task type (e.g., :summarization, :classification, :qa)
  - `max_generations` - Maximum optimization generations (default: 30)

  ## Returns

  - `{:ok, results}` - Optimization results with Pareto frontier
  - `{:error, reason}` - Optimization failed

  ## Examples

      {:ok, results} = optimize_prompt(
        initial_prompt: "Answer this question briefly",
        task: :qa,
        max_generations: 20
      )

      # Results structure:
      # %{
      #   pareto_frontier: [%Candidate{}, ...],
      #   total_generations: 15,
      #   total_evaluations: 750,
      #   convergence_reason: :fitness_plateau,
      #   best_by_objective: %{
      #     accuracy: %Candidate{},
      #     cost: %Candidate{},
      #     latency: %Candidate{},
      #     robustness: %Candidate{}
      #   }
      # }
  """
  @spec optimize_prompt(keyword()) :: {:ok, map()} | {:error, term()}
  def optimize_prompt(opts) do
    initial_prompt = Keyword.fetch!(opts, :initial_prompt)
    task = Keyword.fetch!(opts, :task)
    max_generations = Keyword.get(opts, :max_generations, 30)

    Logger.info("Starting GEPA optimization for #{task} task")
    Logger.info("Initial prompt: #{initial_prompt}")

    # Create initial population
    {:ok, population} = create_initial_population(initial_prompt, task)

    # Configure optimization
    config = %{
      population_size: 50,
      max_generations: max_generations,
      objectives: [:accuracy, :latency, :cost, :robustness],
      objective_directions: %{
        accuracy: :maximize,
        latency: :minimize,  # Lower latency is better
        cost: :minimize,     # Lower cost is better
        robustness: :maximize
      },
      convergence: %{
        plateau_patience: 5,
        diversity_threshold: 0.3,
        budget_limit: max_generations * 50  # max_gen * pop_size
      },
      selection: %{
        tournament_size: 3,
        elite_fraction: 0.1
      },
      mutation: %{
        rate: 0.3,
        types: [:word_swap, :instruction_variation, :format_change]
      }
    }

    # Run optimization
    Logger.info("Running optimization with config: #{inspect(config, pretty: true)}")
    results = run_optimization(population, config, task)

    Logger.info("Optimization completed:")
    Logger.info("  Generations: #{results.total_generations}")
    Logger.info("  Evaluations: #{results.total_evaluations}")
    Logger.info("  Convergence: #{results.convergence_reason}")
    Logger.info("  Frontier size: #{length(results.pareto_frontier)}")

    {:ok, results}
  end

  @doc """
  Advanced optimization with custom configuration.

  Provides full control over population size, objectives, convergence criteria,
  and optimization strategies.

  ## Parameters

  - `initial_prompt` - Starting prompt to optimize
  - `task` - Task type
  - `config` - Full optimization configuration

  ## Configuration Options

  - `:population_size` - Number of candidates per generation (default: 50)
  - `:max_generations` - Maximum generations (default: 30)
  - `:objectives` - List of objectives to optimize (default: all 4)
  - `:objective_directions` - :maximize or :minimize per objective
  - `:convergence` - Convergence detection settings
  - `:selection` - Selection mechanism parameters
  - `:mutation` - Mutation strategy configuration

  ## Examples

      {:ok, results} = optimize_with_config(
        initial_prompt: "Classify sentiment",
        task: :sentiment,
        config: %{
          population_size: 100,
          max_generations: 50,
          objectives: [:accuracy, :cost],  # Only optimize these two
          convergence: %{
            plateau_patience: 10,
            min_improvement: 0.02
          }
        }
      )
  """
  @spec optimize_with_config(keyword()) :: {:ok, map()} | {:error, term()}
  def optimize_with_config(opts) do
    initial_prompt = Keyword.fetch!(opts, :initial_prompt)
    task = Keyword.fetch!(opts, :task)
    custom_config = Keyword.fetch!(opts, :config)

    Logger.info("Starting advanced GEPA optimization")

    # Create initial population
    {:ok, population} = create_initial_population(
      initial_prompt,
      task,
      custom_config[:population_size] || 50
    )

    # Merge with defaults
    config = Map.merge(default_config(), custom_config)

    # Run optimization
    results = run_optimization(population, config, task)

    {:ok, results}
  end

  @doc """
  Select the fastest solution from Pareto frontier.

  Chooses the solution with lowest latency (best response time).
  May sacrifice some accuracy for speed.

  ## Examples

      frontier = results.pareto_frontier
      fast = select_fast_solution(frontier)
      IO.puts("Fast solution: #{fast.prompt}")
      IO.puts("Latency: #{fast.objectives.latency}ms")
      IO.puts("Accuracy: #{fast.objectives.accuracy}")
  """
  @spec select_fast_solution(list(Candidate.t())) :: Candidate.t()
  def select_fast_solution(frontier) do
    Enum.min_by(frontier, fn c -> c.objectives.latency end)
  end

  @doc """
  Select the most accurate solution from Pareto frontier.

  Chooses the solution with highest accuracy.
  May be slower or more expensive.

  ## Examples

      frontier = results.pareto_frontier
      accurate = select_accurate_solution(frontier)
      IO.puts("Accurate solution: #{accurate.prompt}")
      IO.puts("Accuracy: #{accurate.objectives.accuracy}")
      IO.puts("Cost: $#{accurate.objectives.cost}")
  """
  @spec select_accurate_solution(list(Candidate.t())) :: Candidate.t()
  def select_accurate_solution(frontier) do
    Enum.max_by(frontier, fn c -> c.objectives.accuracy end)
  end

  @doc """
  Select the most cost-efficient solution from Pareto frontier.

  Chooses the solution with lowest cost per evaluation.

  ## Examples

      frontier = results.pareto_frontier
      cheap = select_cost_efficient_solution(frontier)
      IO.puts("Cost-efficient solution: #{cheap.prompt}")
      IO.puts("Cost: $#{cheap.objectives.cost}")
  """
  @spec select_cost_efficient_solution(list(Candidate.t())) :: Candidate.t()
  def select_cost_efficient_solution(frontier) do
    Enum.min_by(frontier, fn c -> c.objectives.cost end)
  end

  @doc """
  Select a balanced solution from Pareto frontier.

  Uses a weighted scoring function to find the solution with the best
  overall balance across all objectives.

  Default weights: accuracy=0.4, latency=0.2, cost=0.2, robustness=0.2

  ## Examples

      frontier = results.pareto_frontier
      balanced = select_balanced_solution(frontier)
      IO.puts("Balanced solution: #{balanced.prompt}")

      # Custom weights
      balanced = select_balanced_solution(frontier,
        weights: %{accuracy: 0.5, latency: 0.3, cost: 0.1, robustness: 0.1}
      )
  """
  @spec select_balanced_solution(list(Candidate.t()), keyword()) :: Candidate.t()
  def select_balanced_solution(frontier, opts \\ []) do
    weights = Keyword.get(opts, :weights, %{
      accuracy: 0.4,
      latency: 0.2,
      cost: 0.2,
      robustness: 0.2
    })

    # Normalize objectives to [0, 1] for comparison
    normalized = normalize_frontier_objectives(frontier)

    # Calculate weighted scores
    Enum.max_by(normalized, fn {candidate, norm_obj} ->
      weights[:accuracy] * norm_obj.accuracy +
      weights[:latency] * (1.0 - norm_obj.latency) +  # Invert (lower is better)
      weights[:cost] * (1.0 - norm_obj.cost) +        # Invert (lower is better)
      weights[:robustness] * norm_obj.robustness
    end)
    |> elem(0)  # Return candidate, not tuple
  end

  @doc """
  Visualize the Pareto frontier trade-offs.

  Prints a summary of solutions showing the trade-off between objectives.

  ## Examples

      visualize_frontier(results.pareto_frontier)

      # Output:
      # === Pareto Frontier (8 solutions) ===
      #
      # Solution 1: High Accuracy Focus
      #   Accuracy:   0.92 ████████████████████
      #   Latency:    450ms
      #   Cost:       $0.008
      #   Robustness: 0.85
      #
      # Solution 2: Fast & Cheap
      #   Accuracy:   0.75 ███████████████
      #   Latency:    120ms
      #   Cost:       $0.002
      #   Robustness: 0.78
      # ...
  """
  @spec visualize_frontier(list(Candidate.t())) :: :ok
  def visualize_frontier(frontier) do
    IO.puts("\n=== Pareto Frontier (#{length(frontier)} solutions) ===\n")

    frontier
    |> Enum.with_index(1)
    |> Enum.each(fn {candidate, idx} ->
      category = categorize_solution(candidate)

      IO.puts("Solution #{idx}: #{category}")
      IO.puts("  Prompt: #{String.slice(candidate.prompt, 0..60)}...")
      IO.puts("  Accuracy:   #{format_score(candidate.objectives.accuracy)}")
      IO.puts("  Latency:    #{round(candidate.objectives.latency)}ms")
      IO.puts("  Cost:       $#{Float.round(candidate.objectives.cost, 4)}")
      IO.puts("  Robustness: #{Float.round(candidate.objectives.robustness, 2)}")
      IO.puts("")
    end)

    :ok
  end

  # Private functions

  defp create_initial_population(initial_prompt, task, size \\ 50) do
    Logger.info("Creating initial population of #{size} candidates")

    # Generate variations of the initial prompt
    candidates = Enum.map(1..size, fn i ->
      # In real implementation, this would use mutation strategies
      # For example purposes, we'll create placeholder candidates
      prompt = if i == 1 do
        initial_prompt
      else
        mutate_prompt(initial_prompt, i)
      end

      %Candidate{
        id: "init_#{i}",
        prompt: prompt,
        generation: 0,
        parent_ids: [],
        fitness: 0.0,  # Will be evaluated
        objectives: %{},
        normalized_objectives: %{},
        metadata: %{task: task, source: :initial}
      }
    end)

    {:ok, candidates}
  end

  defp mutate_prompt(prompt, seed) do
    # Placeholder mutation - in real implementation would use GEPA mutation strategies
    "#{prompt} [variation #{seed}]"
  end

  defp run_optimization(population, config, task) do
    # Initialize convergence detector
    detector = Convergence.Detector.new(
      plateau_opts: [
        patience: config.convergence[:plateau_patience] || 5,
        window_size: 5
      ],
      diversity_opts: [
        threshold: config.convergence[:diversity_threshold] || 0.3
      ],
      budget_opts: [
        max_evaluations: config.convergence[:budget_limit]
      ]
    )

    # Initialize frontier manager
    {:ok, frontier_manager} = FrontierManager.new(
      objectives: config.objectives,
      objective_directions: config.objective_directions
    )

    # Simulate optimization loop
    # In real implementation, this would:
    # 1. Evaluate candidates
    # 2. Perform selection
    # 3. Apply crossover
    # 4. Apply mutation
    # 5. Update frontier
    # 6. Check convergence

    # For example purposes, return simulated results
    %{
      pareto_frontier: simulate_frontier(population, config),
      total_generations: config.max_generations,
      total_evaluations: config.max_generations * config.population_size,
      convergence_reason: :fitness_plateau,
      best_by_objective: extract_best_by_objective(population)
    }
  end

  defp simulate_frontier(population, config) do
    # For example purposes, simulate a frontier
    # In real implementation, this would be extracted from actual optimization
    Enum.take(population, 8)
    |> Enum.with_index()
    |> Enum.map(fn {candidate, idx} ->
      # Simulate different trade-off points
      position = idx / 7

      %{candidate |
        objectives: %{
          accuracy: 0.65 + position * 0.25,
          latency: 500 - position * 350,
          cost: 0.010 - position * 0.007,
          robustness: 0.70 + :rand.uniform() * 0.15
        },
        fitness: 0.65 + position * 0.25
      }
    end)
  end

  defp extract_best_by_objective(population) do
    %{
      accuracy: Enum.max_by(population, fn c -> c.objectives[:accuracy] || 0 end),
      latency: Enum.min_by(population, fn c -> c.objectives[:latency] || 1000 end),
      cost: Enum.min_by(population, fn c -> c.objectives[:cost] || 1.0 end),
      robustness: Enum.max_by(population, fn c -> c.objectives[:robustness] || 0 end)
    }
  end

  defp normalize_frontier_objectives(frontier) do
    # Find min/max for each objective
    accuracy_range = get_objective_range(frontier, :accuracy)
    latency_range = get_objective_range(frontier, :latency)
    cost_range = get_objective_range(frontier, :cost)
    robustness_range = get_objective_range(frontier, :robustness)

    Enum.map(frontier, fn candidate ->
      normalized = %{
        accuracy: normalize_value(candidate.objectives.accuracy, accuracy_range),
        latency: normalize_value(candidate.objectives.latency, latency_range),
        cost: normalize_value(candidate.objectives.cost, cost_range),
        robustness: normalize_value(candidate.objectives.robustness, robustness_range)
      }
      {candidate, normalized}
    end)
  end

  defp get_objective_range(frontier, objective) do
    values = Enum.map(frontier, fn c -> Map.get(c.objectives, objective) end)
    {Enum.min(values), Enum.max(values)}
  end

  defp normalize_value(value, {min, max}) when max > min do
    (value - min) / (max - min)
  end
  defp normalize_value(_value, _range), do: 0.5  # Fallback if no range

  defp categorize_solution(candidate) do
    obj = candidate.objectives

    cond do
      obj.accuracy > 0.85 and obj.cost > 0.007 -> "High Accuracy Focus"
      obj.latency < 200 and obj.cost < 0.004 -> "Fast & Cheap"
      obj.accuracy > 0.80 and obj.robustness > 0.85 -> "Accurate & Robust"
      obj.cost < 0.003 -> "Budget Optimized"
      true -> "Balanced"
    end
  end

  defp format_score(score) do
    bars = round(score * 20)
    bar_string = String.duplicate("█", bars)
    "#{Float.round(score, 2)} #{bar_string}"
  end

  defp default_config do
    %{
      population_size: 50,
      max_generations: 30,
      objectives: [:accuracy, :latency, :cost, :robustness],
      objective_directions: %{
        accuracy: :maximize,
        latency: :minimize,
        cost: :minimize,
        robustness: :maximize
      },
      convergence: %{
        plateau_patience: 5,
        diversity_threshold: 0.3,
        min_improvement: 0.01
      },
      selection: %{
        tournament_size: 3,
        elite_fraction: 0.1
      },
      mutation: %{
        rate: 0.3,
        types: [:word_swap, :instruction_variation, :format_change]
      }
    }
  end
end
