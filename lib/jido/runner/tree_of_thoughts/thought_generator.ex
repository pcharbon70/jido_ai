defmodule Jido.Runner.TreeOfThoughts.ThoughtGenerator do
  @moduledoc """
  Thought generation strategies for Tree-of-Thoughts.

  Generates diverse candidate thoughts at each tree node using:
  - **Sampling**: Temperature-based diverse i.i.d. thoughts
  - **Proposal**: Sequential deliberate thought generation
  - **Beam Width**: Configurable k thoughts per node
  - **Adaptive**: Dynamic k based on depth and tree size

  ## Strategies

  ### Sampling Strategy
  Uses high temperature (0.7-1.0) to generate diverse independent thoughts.
  Good for creative exploration and generating varied approaches.

  ### Proposal Strategy
  Uses lower temperature (0.3-0.5) for deliberate, sequential thoughts.
  Each thought builds on previous ones. Good for structured problems.

  ## Examples

      # Sampling strategy (creative)
      {:ok, thoughts} = ThoughtGenerator.generate(
        problem: "Solve 24 with numbers 4, 5, 6, 6",
        parent_state: %{numbers: [4,5,6,6]},
        strategy: :sampling,
        beam_width: 5,
        temperature: 0.8
      )

      # Proposal strategy (structured)
      {:ok, thoughts} = ThoughtGenerator.generate(
        problem: "Write quicksort in Elixir",
        parent_state: %{},
        strategy: :proposal,
        beam_width: 3
      )
  """

  require Logger

  @default_beam_width 5
  @default_temperature 0.7
  @sampling_temperature 0.8
  @proposal_temperature 0.4

  @type generation_opts :: [
          problem: String.t(),
          parent_state: map(),
          strategy: :sampling | :proposal | :adaptive,
          beam_width: pos_integer(),
          temperature: float(),
          depth: non_neg_integer(),
          tree_size: non_neg_integer(),
          thought_fn: function() | nil
        ]

  @doc """
  Generates candidate thoughts for expansion.

  ## Parameters

  - `opts` - Generation options:
    - `:problem` - The problem being solved (required)
    - `:parent_state` - State at parent node (required)
    - `:strategy` - Generation strategy (:sampling, :proposal, :adaptive)
    - `:beam_width` - Number of thoughts to generate (default: 5)
    - `:temperature` - LLM temperature (default: 0.7)
    - `:depth` - Current depth in tree
    - `:tree_size` - Current tree size
    - `:thought_fn` - Custom thought generation function (for testing)

  ## Returns

  - `{:ok, thoughts}` - List of thought strings
  - `{:error, reason}` - Generation failed

  ## Examples

      {:ok, thoughts} = ThoughtGenerator.generate(
        problem: "What is 15% of 80?",
        parent_state: %{},
        strategy: :sampling,
        beam_width: 5
      )
      # => {:ok, ["Approach 1: Convert to decimal...", "Approach 2: Use fraction...", ...]}
  """
  @spec generate(generation_opts()) :: {:ok, list(String.t())} | {:error, term()}
  def generate(opts) do
    problem = Keyword.fetch!(opts, :problem)
    parent_state = Keyword.fetch!(opts, :parent_state)
    strategy = Keyword.get(opts, :strategy, :sampling)
    beam_width = Keyword.get(opts, :beam_width, @default_beam_width)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    depth = Keyword.get(opts, :depth, 0)
    tree_size = Keyword.get(opts, :tree_size, 0)
    thought_fn = Keyword.get(opts, :thought_fn)

    # Determine effective beam width (adaptive if needed)
    effective_beam_width =
      if strategy == :adaptive do
        adaptive_beam_width(beam_width, depth, tree_size)
      else
        beam_width
      end

    # Determine effective temperature
    effective_temperature =
      case strategy do
        :sampling -> Keyword.get(opts, :temperature, @sampling_temperature)
        :proposal -> Keyword.get(opts, :temperature, @proposal_temperature)
        :adaptive -> temperature
      end

    Logger.debug(
      "Generating #{effective_beam_width} thoughts with strategy: #{strategy}, temp: #{effective_temperature}"
    )

    # Use custom thought function if provided (for testing)
    if thought_fn do
      thoughts = thought_fn.(opts)
      {:ok, thoughts}
    else
      case strategy do
        :sampling -> generate_sampling(problem, parent_state, effective_beam_width, effective_temperature)
        :proposal -> generate_proposal(problem, parent_state, effective_beam_width, effective_temperature)
        :adaptive -> generate_sampling(problem, parent_state, effective_beam_width, effective_temperature)
      end
    end
  end

  @doc """
  Calculates adaptive beam width based on depth and tree size.

  Reduces beam width at deeper levels to control exponential growth.

  ## Parameters

  - `base_beam_width` - Base beam width
  - `depth` - Current depth
  - `tree_size` - Current tree size

  ## Returns

  Adjusted beam width
  """
  @spec adaptive_beam_width(pos_integer(), non_neg_integer(), non_neg_integer()) :: pos_integer()
  def adaptive_beam_width(base_beam_width, depth, tree_size) do
    # Reduce beam width as depth increases
    depth_factor = max(1, base_beam_width - div(depth, 2))

    # Reduce if tree is getting too large
    size_factor =
      cond do
        tree_size > 1000 -> max(2, div(base_beam_width, 2))
        tree_size > 500 -> max(3, base_beam_width - 1)
        true -> base_beam_width
      end

    min(depth_factor, size_factor)
  end

  # Private functions

  defp generate_sampling(problem, parent_state, beam_width, temperature) do
    # Sampling strategy: Generate diverse i.i.d. thoughts in parallel
    # Each thought is independent, exploring different approaches

    _prompt = build_sampling_prompt(problem, parent_state, beam_width)

    # In production, this would call LLM
    # For now, simulate diverse thoughts
    thoughts = simulate_sampling_thoughts(problem, parent_state, beam_width, temperature)

    {:ok, thoughts}
  end

  defp generate_proposal(problem, parent_state, beam_width, temperature) do
    # Proposal strategy: Generate thoughts sequentially
    # Each thought is aware of previous proposals

    thoughts = simulate_proposal_thoughts(problem, parent_state, beam_width, temperature)

    {:ok, thoughts}
  end

  defp build_sampling_prompt(problem, parent_state, k) do
    """
    Problem: #{problem}

    Current state: #{inspect(parent_state, pretty: true)}

    Generate #{k} diverse approaches to solve this problem.
    Each approach should be distinct and explore a different strategy.

    Format each thought as a clear, actionable step.
    """
  end

  defp simulate_sampling_thoughts(problem, _parent_state, beam_width, _temperature) do
    # Simulate diverse thoughts for testing
    # In production, this would be actual LLM calls

    base_thoughts = [
      "Try a direct calculation approach",
      "Break the problem into smaller sub-problems",
      "Look for patterns or formulas that apply",
      "Work backwards from the desired outcome",
      "Use a systematic elimination strategy",
      "Apply domain-specific knowledge",
      "Consider edge cases and special conditions",
      "Reformulate the problem in a different way"
    ]

    base_thoughts
    |> Enum.take(beam_width)
    |> Enum.with_index()
    |> Enum.map(fn {thought, i} ->
      "#{thought} for: #{String.slice(problem, 0, 30)}... (option #{i + 1})"
    end)
  end

  defp simulate_proposal_thoughts(problem, _parent_state, beam_width, _temperature) do
    # Simulate sequential proposal thoughts
    # Each builds on understanding from previous

    Enum.map(1..beam_width, fn i ->
      cond do
        i == 1 ->
          "Initial approach: Analyze the problem structure - #{String.slice(problem, 0, 30)}..."

        i == 2 ->
          "Alternative: Based on initial analysis, try a different method"

        i == 3 ->
          "Refined approach: Combine insights from previous proposals"

        true ->
          "Extended approach #{i}: Explore additional variations"
      end
    end)
  end
end
