defmodule Jido.Runner.TreeOfThoughts.ThoughtEvaluator do
  @moduledoc """
  Thought evaluation strategies for Tree-of-Thoughts.

  Evaluates the quality and promise of thoughts to guide search:
  - **Value**: LLM scores thought viability (0=impossible, 0.5=maybe, 1=sure)
  - **Vote**: Multiple evaluations with majority voting
  - **Heuristic**: Domain-specific quality metrics
  - **Hybrid**: Combine multiple evaluation strategies

  ## Evaluation Strategies

  ### Value Evaluation
  Single LLM call returns scalar value 0.0-1.0 indicating thought quality.
  Fast, lower cost, but single opinion.

  ### Vote Evaluation
  Multiple LLM evaluations (typically 3-5) vote on thought quality.
  More robust, catches errors, but higher cost.

  ### Heuristic Evaluation
  Domain-specific rules and metrics (e.g., code syntax, math validity).
  Fast, deterministic, but requires domain knowledge.

  ### Hybrid Evaluation
  Combines multiple strategies for best accuracy/cost tradeoff.

  ## Examples

      # Value evaluation
      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "Try approach X",
        problem: "Solve Y",
        strategy: :value
      )

      # Vote evaluation (more robust)
      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "Complex step",
        problem: "Hard problem",
        strategy: :vote,
        num_votes: 5
      )

      # Heuristic (domain-specific)
      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "def foo(x): return x*2",
        problem: "Write doubling function",
        strategy: :heuristic,
        heuristic_fn: &code_validity_score/1
      )
  """

  require Logger

  @type evaluation_opts :: [
          thought: String.t(),
          problem: String.t(),
          state: map(),
          strategy: :value | :vote | :heuristic | :hybrid,
          num_votes: pos_integer(),
          heuristic_fn: function() | nil,
          evaluation_fn: function() | nil
        ]

  @doc """
  Evaluates a thought's quality and promise.

  ## Parameters

  - `opts` - Evaluation options:
    - `:thought` - The thought to evaluate (required)
    - `:problem` - The problem context (required)
    - `:state` - Current state (default: %{})
    - `:strategy` - Evaluation strategy (default: :value)
    - `:num_votes` - Number of votes for vote strategy (default: 3)
    - `:heuristic_fn` - Custom heuristic function
    - `:evaluation_fn` - Custom evaluation function (for testing)

  ## Returns

  - `{:ok, score}` - Score from 0.0 to 1.0
  - `{:error, reason}` - Evaluation failed

  ## Examples

      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "Break problem into sub-problems",
        problem: "Solve complex task",
        strategy: :value
      )
      # => {:ok, 0.75}
  """
  @spec evaluate(evaluation_opts()) :: {:ok, float()} | {:error, term()}
  def evaluate(opts) do
    thought = Keyword.fetch!(opts, :thought)
    problem = Keyword.fetch!(opts, :problem)
    state = Keyword.get(opts, :state, %{})
    strategy = Keyword.get(opts, :strategy, :value)
    num_votes = Keyword.get(opts, :num_votes, 3)
    heuristic_fn = Keyword.get(opts, :heuristic_fn)
    evaluation_fn = Keyword.get(opts, :evaluation_fn)

    Logger.debug("Evaluating thought with strategy: #{strategy}")

    # Use custom evaluation function if provided (for testing)
    if evaluation_fn do
      {:ok, evaluation_fn.(opts)}
    else
      case strategy do
        :value -> evaluate_value(thought, problem, state)
        :vote -> evaluate_vote(thought, problem, state, num_votes)
        :heuristic -> evaluate_heuristic(thought, problem, state, heuristic_fn)
        :hybrid -> evaluate_hybrid(thought, problem, state, num_votes, heuristic_fn)
      end
    end
  end

  @doc """
  Evaluates multiple thoughts in batch.

  More efficient than individual evaluation when using LLM-based strategies.

  ## Parameters

  - `thoughts` - List of thoughts to evaluate
  - `opts` - Same as evaluate/1

  ## Returns

  - `{:ok, scores}` - List of scores matching thoughts order
  - `{:error, reason}` - Evaluation failed
  """
  @spec evaluate_batch(list(String.t()), evaluation_opts()) ::
          {:ok, list(float())} | {:error, term()}
  def evaluate_batch(thoughts, opts) do
    # For now, evaluate individually
    # In production, could batch LLM calls for efficiency
    results =
      Enum.map(thoughts, fn thought ->
        case evaluate(Keyword.put(opts, :thought, thought)) do
          {:ok, score} -> score
          {:error, _} -> 0.5
          # Default to neutral on error
        end
      end)

    {:ok, results}
  end

  # Private functions

  defp evaluate_value(thought, problem, state) do
    # Value evaluation: Single LLM call for scalar score
    # In production, this would call LLM with value prompt

    score = simulate_value_evaluation(thought, problem, state)
    {:ok, score}
  end

  defp evaluate_vote(thought, problem, state, num_votes) do
    # Vote evaluation: Multiple independent evaluations
    # More robust against single evaluation errors

    votes =
      Enum.map(1..num_votes, fn i ->
        # Each vote would be independent LLM call
        # Add slight variation to simulate independence
        base_score = simulate_value_evaluation(thought, problem, state)
        variation = (i - (num_votes / 2)) * 0.05
        max(0.0, min(1.0, base_score + variation))
      end)

    # Aggregate votes (mean)
    avg_score = Enum.sum(votes) / num_votes

    {:ok, avg_score}
  end

  defp evaluate_heuristic(thought, problem, state, heuristic_fn) do
    # Heuristic evaluation: Domain-specific rules

    score =
      if heuristic_fn do
        heuristic_fn.(%{thought: thought, problem: problem, state: state})
      else
        # Default heuristics
        default_heuristic_score(thought, problem, state)
      end

    {:ok, score}
  end

  defp evaluate_hybrid(thought, problem, state, _num_votes, heuristic_fn) do
    # Hybrid: Combine value, vote, and heuristic

    # Get value score (fast)
    {:ok, value_score} = evaluate_value(thought, problem, state)

    # Get heuristic score (fast, deterministic)
    {:ok, heuristic_score} = evaluate_heuristic(thought, problem, state, heuristic_fn)

    # Combine with weights
    # If heuristic is very confident (close to 0 or 1), trust it more
    heuristic_confidence = abs(heuristic_score - 0.5) * 2

    # Weighted combination
    combined =
      if heuristic_confidence > 0.7 do
        # Trust heuristic more
        heuristic_score * 0.7 + value_score * 0.3
      else
        # Balance heuristic and value
        heuristic_score * 0.4 + value_score * 0.6
      end

    {:ok, combined}
  end

  defp simulate_value_evaluation(thought, problem, _state) do
    # Simulate LLM value evaluation
    # In production, this would be actual LLM call

    # Simple heuristic for simulation
    thought_length = String.length(thought)
    _problem_length = String.length(problem)

    # Longer, more detailed thoughts score higher
    length_score = min(1.0, thought_length / 100.0)

    # Thoughts mentioning key problem terms score higher
    problem_words = problem |> String.downcase() |> String.split()

    relevance_score =
      problem_words
      |> Enum.count(fn word ->
        String.contains?(String.downcase(thought), word)
      end)
      |> Kernel./(max(1, length(problem_words)))

    # Combine factors
    base_score = length_score * 0.3 + relevance_score * 0.7

    # Add some randomness to simulate LLM variability
    noise = (:rand.uniform() - 0.5) * 0.2
    clamped_score = max(0.0, min(1.0, base_score + noise))

    clamped_score
  end

  defp default_heuristic_score(thought, _problem, _state) do
    # Default heuristics when no custom function provided

    score = 0.5

    # Penalize very short thoughts (likely incomplete)
    score =
      if String.length(thought) < 10 do
        score * 0.5
      else
        score
      end

    # Reward thoughts with specific actions or steps
    action_words = ["calculate", "check", "verify", "try", "apply", "use", "consider"]

    has_action =
      Enum.any?(action_words, fn word ->
        String.contains?(String.downcase(thought), word)
      end)

    score =
      if has_action do
        score + 0.2
      else
        score
      end

    # Reward thoughts with conditional logic
    has_conditional = String.contains?(thought, ["if", "when", "unless", "in case"])

    score =
      if has_conditional do
        score + 0.1
      else
        score
      end

    max(0.0, min(1.0, score))
  end
end
