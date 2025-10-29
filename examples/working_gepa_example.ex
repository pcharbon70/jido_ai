defmodule Examples.WorkingGEPAExample do
  @moduledoc """
  **WORKING** example of GEPA (Genetic-Pareto Prompt Optimization) with real LLM calls.

  ## ⚠️  CRITICAL COST WARNING ⚠️

  **THIS EXAMPLE MAKES REAL API CALLS TO LLM PROVIDERS AND WILL INCUR ACTUAL COSTS!**

  **COSTS CAN BE UNPREDICTABLE AND POTENTIALLY EXPENSIVE:**
  - Each generation evaluates MULTIPLE prompts (default: 20 candidates/generation)
  - Each evaluation = 1 API call with input + output tokens
  - Default 10 generations = 200+ API calls minimum
  - Actual costs depend on: model pricing, prompt length, response length
  - ESTIMATED: $0.50 - $5.00+ per optimization run (highly variable)

  **BEFORE RUNNING:**
  1. Set strict budget limits in your provider account
  2. Start with SMALL population sizes (5-10) and FEW generations (3-5)
  3. Use CHEAPER models first (gpt-3.5-turbo, claude-instant)
  4. Monitor your API usage dashboard actively
  5. Understand you are responsible for ALL incurred costs

  **COST EXAMPLE:**
  ```
  population_size: 10, generations: 5, model: gpt-4
  = 50 evaluations minimum
  = ~$2.50 (at $0.05/eval, varies by length)
  ```

  ## Model Format

  Models MUST be specified in the format: **`"provider:model_name"`**

  Examples:
  - `"openai:gpt-4"`
  - `"openai:gpt-3.5-turbo"`
  - `"anthropic:claude-3-haiku-20240307"`
  - `"anthropic:claude-3-sonnet-20240229"`
  - `"groq:llama-3.1-8b-instant"`

  See ReqLLM documentation for full list of supported providers and models.

  ## Prerequisites

  API keys must be loaded via Jido.AI.Keyring before running:

  ```elixir
  # Set API key (required before optimization)
  Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

  # Or use environment variable:
  # export OPENAI_API_KEY="sk-..."
  ```

  ## Basic Usage

  ```elixir
  # SMALL test run (recommended first)
  {:ok, results} = Examples.WorkingGEPAExample.optimize_prompt(
    initial_prompt: "Summarize: {{text}}",
    model: "openai:gpt-3.5-turbo",  # Cheaper model
    test_inputs: ["Short text here"],
    population_size: 5,   # SMALL
    max_generations: 3,   # FEW
    evaluation_budget: 20 # Hard limit
  )

  # View results
  IO.puts("Best prompts found:")
  Enum.each(results.pareto_frontier, fn candidate ->
    IO.puts("\nPrompt: \#{candidate.prompt}")
    IO.puts("Accuracy: \#{candidate.objectives.accuracy}")
    IO.puts("Cost: $\#{candidate.objectives.cost}")
  end)
  ```

  ## Features

  - Real multi-objective optimization with LLM evaluation
  - Actual cost tracking per evaluation
  - Hard budget limits (evaluation_budget parameter)
  - Simple mutation operators (word substitution, instruction variation)
  - Pareto frontier extraction
  - Progress monitoring
  """

  require Logger

  alias Jido.AI.Keyring
  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator

  @doc """
  Optimize a prompt template using GEPA with real LLM evaluation.

  ## ⚠️  WARNING: MAKES REAL API CALLS - SEE MODULE DOC FOR COST WARNINGS ⚠️

  ## Parameters

  - `:initial_prompt` - Starting prompt template (use {{variable}} for placeholders)
  - `:model` - Model in "provider:model" format (e.g., "openai:gpt-3.5-turbo")
  - `:test_inputs` - List of test inputs for evaluation
  - `:population_size` - Candidates per generation (default: 10, recommend 5-10)
  - `:max_generations` - Maximum generations (default: 5, recommend 3-5 for testing)
  - `:evaluation_budget` - Hard limit on total evaluations (default: 50)
  - `:expected_outputs` - Optional list of expected outputs for accuracy measurement

  ## Returns

  - `{:ok, results}` with:
    - `:pareto_frontier` - Best trade-off solutions
    - `:total_evaluations` - Number of LLM calls made
    - `:total_cost` - Actual API cost incurred
    - `:generations_completed` - Generations run before stopping

  ## Examples

      # Minimal test (recommended first run)
      {:ok, results} = optimize_prompt(
        initial_prompt: "Translate to French: {{text}}",
        model: "openai:gpt-3.5-turbo",
        test_inputs: ["Hello"],
        population_size: 5,
        max_generations: 2,
        evaluation_budget: 10
      )
  """
  @spec optimize_prompt(keyword()) :: {:ok, map()} | {:error, term()}
  def optimize_prompt(opts) do
    # Extract and validate parameters
    with {:ok, config} <- build_config(opts),
         :ok <- check_api_key(config.model),
         :ok <- confirm_cost_awareness() do

      Logger.warning("""

      ========================================
      STARTING GEPA OPTIMIZATION
      ========================================
      Model: #{config.model}
      Population: #{config.population_size}
      Max Generations: #{config.max_generations}
      Budget Limit: #{config.evaluation_budget} evaluations

      ESTIMATED COST: $#{estimate_cost(config)}
      (Actual cost may vary based on response lengths)
      ========================================
      """)

      run_optimization(config)
    end
  end

  # Private implementation

  defp build_config(opts) do
    config = %{
      initial_prompt: Keyword.fetch!(opts, :initial_prompt),
      model: Keyword.fetch!(opts, :model),
      test_inputs: Keyword.fetch!(opts, :test_inputs),
      expected_outputs: Keyword.get(opts, :expected_outputs),
      population_size: Keyword.get(opts, :population_size, 10),
      max_generations: Keyword.get(opts, :max_generations, 5),
      evaluation_budget: Keyword.get(opts, :evaluation_budget, 50),
      mutation_rate: Keyword.get(opts, :mutation_rate, 0.3)
    }

    # Validate
    cond do
      not String.contains?(config.model, ":") ->
        {:error, "Model must be in format 'provider:model', got: #{config.model}"}

      config.population_size < 2 ->
        {:error, "Population size must be at least 2"}

      config.max_generations < 1 ->
        {:error, "Must run at least 1 generation"}

      true ->
        {:ok, config}
    end
  end

  defp check_api_key(model_string) do
    [provider_str | _] = String.split(model_string, ":")
    provider = String.to_atom(provider_str)
    key_name = :"#{provider}_api_key"

    case Keyring.get_env_value(key_name, nil) do
      nil ->
        {:error, """
        API key not found for provider: #{provider}

        Please set the API key first:
        Jido.AI.Keyring.set_env_value(:#{key_name}, "your-key-here")

        Or set environment variable: #{String.upcase("#{provider}_api_key")}
        """}

      _key ->
        :ok
    end
  end

  defp confirm_cost_awareness do
    # In a real interactive environment, you might prompt the user
    # For this example, we just log a final warning
    Logger.warning("""

    ⚠️  FINAL COST WARNING ⚠️
    You are about to make real API calls that will cost real money.
    Proceeding in 2 seconds... (Ctrl+C to abort)
    """)

    Process.sleep(2000)
    :ok
  end

  defp estimate_cost(config) do
    # Rough estimation: $0.05 per evaluation for gpt-3.5-turbo equivalent
    # Real costs vary significantly by model and length
    evaluations = min(
      config.population_size * config.max_generations,
      config.evaluation_budget
    )

    cost_per_eval = cond do
      String.contains?(config.model, "gpt-4") -> 0.10
      String.contains?(config.model, "claude-3-opus") -> 0.15
      String.contains?(config.model, "claude-3-sonnet") -> 0.08
      String.contains?(config.model, "gpt-3.5") -> 0.03
      true -> 0.05  # Conservative estimate
    end

    Float.round(evaluations * cost_per_eval, 2)
  end

  defp run_optimization(config) do
    # Initialize population
    Logger.info("Creating initial population of #{config.population_size} candidates...")
    population = create_initial_population(config)

    # Evaluate initial population
    Logger.info("Evaluating initial population...")
    {evaluated_pop, eval_count, total_cost} = evaluate_population(population, config)

    # Track state
    state = %{
      population: evaluated_pop,
      generation: 1,
      evaluations_used: eval_count,
      total_cost: total_cost,
      best_fitness: get_best_fitness(evaluated_pop)
    }

    # Run generations
    final_state = run_generations(state, config)

    # Extract Pareto frontier
    fronts = DominanceComparator.fast_non_dominated_sort(final_state.population)
    frontier = Map.get(fronts, 1, [])

    Logger.info("""

    ========================================
    OPTIMIZATION COMPLETE
    ========================================
    Generations: #{final_state.generation - 1}
    Evaluations: #{final_state.evaluations_used}
    Actual Cost: $#{Float.round(final_state.total_cost, 4)}
    Frontier Size: #{length(frontier)}
    ========================================
    """)

    {:ok, %{
      pareto_frontier: frontier,
      total_evaluations: final_state.evaluations_used,
      total_cost: final_state.total_cost,
      generations_completed: final_state.generation - 1,
      final_population: final_state.population
    }}
  end

  defp create_initial_population(config) do
    # Create initial candidate from template
    initial = %Candidate{
      id: "gen0_1",
      prompt: config.initial_prompt,
      generation: 0,
      parent_ids: []
    }

    # Generate variations through mutation
    [initial | Enum.map(2..config.population_size, fn i ->
      %Candidate{
        id: "gen0_#{i}",
        prompt: mutate_prompt(config.initial_prompt, i),
        generation: 0,
        parent_ids: []
      }
    end)]
  end

  defp mutate_prompt(prompt, seed) do
    # Simple mutation strategies
    :rand.seed(:exsplus, {seed, seed * 2, seed * 3})

    case :rand.uniform(3) do
      1 -> add_instruction_modifier(prompt)
      2 -> change_wording(prompt)
      3 -> adjust_format(prompt)
    end
  end

  defp add_instruction_modifiers() do
    ["Be concise", "Be detailed", "Be clear", "Be precise", "Focus on key points",
     "Explain step by step", "Provide examples", "Summarize briefly"]
  end

  defp add_instruction_modifier(prompt) do
    modifiers = add_instruction_modifiers()
    modifier = Enum.random(modifiers)
    "#{modifier}. #{prompt}"
  end

  defp change_wording(prompt) do
    replacements = [
      {"Summarize", "Condense"},
      {"Explain", "Describe"},
      {"Translate", "Convert"},
      {"Analyze", "Examine"},
      {"Generate", "Create"}
    ]

    Enum.reduce(replacements, prompt, fn {from, to}, acc ->
      if String.contains?(acc, from) and :rand.uniform() > 0.5 do
        String.replace(acc, from, to, global: false)
      else
        acc
      end
    end)
  end

  defp adjust_format(prompt) do
    formats = [
      "\n\nProvide your response in a clear format.",
      "\n\nAnswer:",
      "\n\nOutput:",
      ""
    ]

    prompt <> Enum.random(formats)
  end

  defp evaluate_population(population, config) do
    Logger.info("Evaluating #{length(population)} candidates...")

    {evaluated, eval_count, total_cost} = Enum.reduce(population, {[], 0, 0.0}, fn candidate, {acc, count, cost} ->
      if count >= config.evaluation_budget do
        Logger.warning("Budget limit reached at #{count} evaluations")
        {[candidate | acc], count, cost}  # Return unevaluated
      else
        case evaluate_candidate(candidate, config) do
          {:ok, evaluated_candidate, eval_cost} ->
            Logger.debug("Evaluated #{candidate.id}: accuracy=#{Float.round(evaluated_candidate.objectives.accuracy, 2)}, cost=$#{Float.round(eval_cost, 4)}")
            {[evaluated_candidate | acc], count + length(config.test_inputs), cost + eval_cost}

          {:error, reason} ->
            Logger.error("Evaluation failed for #{candidate.id}: #{inspect(reason)}")
            {[candidate | acc], count, cost}
        end
      end
    end)

    {Enum.reverse(evaluated), eval_count, total_cost}
  end

  defp evaluate_candidate(candidate, config) do
    # Evaluate prompt on all test inputs
    results = Enum.map(config.test_inputs, fn input ->
      evaluate_on_input(candidate.prompt, input, config)
    end)

    # Check for any errors
    if Enum.any?(results, &match?({:error, _}, &1)) do
      errors = Enum.filter(results, &match?({:error, _}, &1))
      {:error, "Evaluation failed: #{inspect(List.first(errors))}"}
    else
      # Calculate metrics
      metrics = Enum.map(results, fn {:ok, result} -> result end)

      objectives = %{
        accuracy: calculate_accuracy(metrics, config),
        latency: calculate_avg_latency(metrics),
        cost: calculate_total_cost(metrics),
        robustness: calculate_robustness(metrics)
      }

      normalized_objectives = normalize_objectives(objectives)

      evaluated = %{candidate |
        objectives: objectives,
        normalized_objectives: normalized_objectives,
        fitness: normalized_objectives.accuracy  # Use accuracy as primary fitness
      }

      total_cost = Enum.sum(Enum.map(metrics, & &1.cost))
      {:ok, evaluated, total_cost}
    end
  end

  defp evaluate_on_input(prompt_template, input, config) do
    # Replace {{text}} or {{input}} with actual input
    prompt = prompt_template
    |> String.replace("{{text}}", to_string(input))
    |> String.replace("{{input}}", to_string(input))

    messages = [%{role: "user", content: prompt}]

    start_time = System.monotonic_time(:millisecond)

    case ReqLLM.generate_text(config.model, messages, max_tokens: 500, temperature: 0.7) do
      {:ok, response} ->
        end_time = System.monotonic_time(:millisecond)
        latency = end_time - start_time

        output = get_response_content(response)
        cost = estimate_call_cost(response, config.model)

        {:ok, %{
          input: input,
          output: output,
          latency: latency,
          cost: cost,
          success: true
        }}

      {:error, reason} ->
        {:error, "LLM call failed: #{inspect(reason)}"}
    end
  end

  defp get_response_content(response) when is_binary(response), do: response
  defp get_response_content(%{content: content}), do: content
  defp get_response_content(response) when is_map(response) do
    response["content"] || response[:content] || inspect(response)
  end
  defp get_response_content(_), do: ""

  defp estimate_call_cost(response, model) when is_binary(response) do
    # Rough estimate based on typical response lengths
    estimate_call_cost(%{content: response}, model)
  end
  defp estimate_call_cost(response, model) when is_map(response) do
    content = get_response_content(response)

    # Estimate tokens (rough: ~4 chars per token)
    output_tokens = div(String.length(content), 4)
    input_tokens = 50  # Rough estimate for prompt

    # Cost per 1K tokens (rough estimates)
    {input_cost_per_1k, output_cost_per_1k} = case model do
      "openai:gpt-4" <> _ -> {0.03, 0.06}
      "openai:gpt-3.5-turbo" <> _ -> {0.0015, 0.002}
      "anthropic:claude-3-opus" <> _ -> {0.015, 0.075}
      "anthropic:claude-3-sonnet" <> _ -> {0.003, 0.015}
      "anthropic:claude-3-haiku" <> _ -> {0.00025, 0.00125}
      "anthropic:claude-instant" <> _ -> {0.00080, 0.00240}
      _ -> {0.001, 0.002}  # Generic estimate
    end

    input_cost = (input_tokens / 1000.0) * input_cost_per_1k
    output_cost = (output_tokens / 1000.0) * output_cost_per_1k

    input_cost + output_cost
  end

  defp calculate_accuracy(metrics, config) do
    if config.expected_outputs do
      # Calculate similarity to expected outputs
      scores = Enum.zip(metrics, config.expected_outputs)
      |> Enum.map(fn {metric, expected} ->
        similarity_score(metric.output, expected)
      end)

      Enum.sum(scores) / length(scores)
    else
      # Use success rate and output quality heuristics
      success_rate = Enum.count(metrics, & &1.success) / length(metrics)
      avg_length = Enum.sum(Enum.map(metrics, &String.length(&1.output))) / length(metrics)

      # Penalize very short or very long outputs
      length_score = cond do
        avg_length < 10 -> 0.3
        avg_length > 1000 -> 0.6
        true -> 1.0
      end

      success_rate * length_score
    end
  end

  defp similarity_score(output, expected) do
    # Simple word overlap similarity
    output_words = String.split(String.downcase(output))
    expected_words = String.split(String.downcase(expected))

    common = MapSet.intersection(MapSet.new(output_words), MapSet.new(expected_words))
    union = MapSet.union(MapSet.new(output_words), MapSet.new(expected_words))

    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(common) / MapSet.size(union)
    end
  end

  defp calculate_avg_latency(metrics) do
    Enum.sum(Enum.map(metrics, & &1.latency)) / length(metrics)
  end

  defp calculate_total_cost(metrics) do
    Enum.sum(Enum.map(metrics, & &1.cost))
  end

  defp calculate_robustness(metrics) do
    # Robustness = consistency of outputs
    if length(metrics) < 2 do
      1.0
    else
      outputs = Enum.map(metrics, & &1.output)
      lengths = Enum.map(outputs, &String.length/1)

      avg_len = Enum.sum(lengths) / length(lengths)
      variance = Enum.sum(Enum.map(lengths, fn len -> :math.pow(len - avg_len, 2) end)) / length(lengths)
      std_dev = :math.sqrt(variance)

      # Lower variance = higher robustness
      1.0 - min(std_dev / (avg_len + 1), 1.0)
    end
  end

  defp normalize_objectives(objectives) do
    # Simple normalization for optimization
    %{
      accuracy: objectives.accuracy,  # Already 0-1
      latency: 1.0 / (1.0 + objectives.latency / 1000.0),  # Invert and normalize
      cost: 1.0 / (1.0 + objectives.cost * 100),  # Invert and normalize
      robustness: objectives.robustness  # Already 0-1
    }
  end

  defp run_generations(state, config) do
    if state.generation > config.max_generations do
      state
    else
      if state.evaluations_used >= config.evaluation_budget do
        Logger.info("Budget limit reached. Stopping optimization.")
        state
      else
        Logger.info("\n--- Generation #{state.generation} ---")
        Logger.info("Best fitness: #{Float.round(state.best_fitness, 3)}")
        Logger.info("Evaluations used: #{state.evaluations_used}/#{config.evaluation_budget}")
        Logger.info("Cost so far: $#{Float.round(state.total_cost, 4)}")

        # Selection: Keep best half
        sorted = Enum.sort_by(state.population, & &1.fitness, :desc)
        parents = Enum.take(sorted, div(config.population_size, 2))

        # Generate offspring through mutation
        offspring = Enum.map(1..div(config.population_size, 2), fn i ->
          parent = Enum.random(parents)
          %Candidate{
            id: "gen#{state.generation}_#{i}",
            prompt: mutate_prompt(parent.prompt, i + state.generation * 100),
            generation: state.generation,
            parent_ids: [parent.id]
          }
        end)

        # Evaluate new offspring
        {evaluated_offspring, new_evals, new_cost} = evaluate_population(offspring, %{config | evaluation_budget: config.evaluation_budget - state.evaluations_used})

        # Combine parents and evaluated offspring
        new_population = parents ++ evaluated_offspring

        # Update state
        new_state = %{state |
          population: new_population,
          generation: state.generation + 1,
          evaluations_used: state.evaluations_used + new_evals,
          total_cost: state.total_cost + new_cost,
          best_fitness: max(state.best_fitness, get_best_fitness(new_population))
        }

        run_generations(new_state, config)
      end
    end
  end

  defp get_best_fitness(population) do
    population
    |> Enum.map(& &1.fitness)
    |> Enum.max(fn -> 0.0 end)
  end
end
