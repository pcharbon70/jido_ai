# GEPA: Genetic-Pareto Prompt Optimization

## Introduction

GEPA (Genetic-Pareto) is an evolutionary optimization system for automatically improving prompts and other text-based components of AI systems. Unlike traditional methods that require thousands of trial runs, GEPA uses the LLM itself as a reflective coach to efficiently evolve high-quality prompts through natural language feedback.

The key innovation is treating prompt optimization as an **evolutionary search problem** guided by the AI's own feedback. GEPA maintains a diverse set of high-performing prompts along a **Pareto frontier**, meaning it considers multiple objectives simultaneously and keeps prompts that excel in different aspects.

### Why GEPA?

- **Sample Efficient**: Achieves large performance gains with far fewer trials than reinforcement learning (up to 35× fewer rollouts)
- **Multi-Objective**: Optimizes for multiple competing goals simultaneously (accuracy, speed, cost, robustness)
- **Language-Driven**: Uses natural language reflection to propose targeted improvements
- **Diverse Solutions**: Maintains multiple high-quality prompts for different trade-offs
- **Elixir Native**: Leverages Elixir's concurrency to evaluate prompts in parallel

### Performance

In experiments, GEPA outperformed reinforcement learning baselines by ~10% on average (up to 19% on certain benchmarks) while using significantly fewer evaluations. It also surpassed prior prompt optimizers like MIPROv2, more than doubling the quality improvement achieved.

---

## Core Concepts

### Multi-Objective Optimization

Traditional optimization seeks a single "best" solution. GEPA uses **multi-objective optimization** to find multiple solutions that represent different trade-offs:

```elixir
# Example: Optimize for multiple objectives
objectives = [:accuracy, :latency, :cost, :robustness]

# Result: A Pareto frontier of solutions
# - Prompt A: High accuracy, slower, more expensive
# - Prompt B: Lower accuracy, faster, cheaper
# - Prompt C: Balanced across all objectives
```

### The Pareto Frontier

A solution is **Pareto optimal** if you cannot improve one objective without making another worse. GEPA maintains a population of Pareto optimal prompts:

```
Cost ↓
  │     ◆ High accuracy, high cost
  │   ◆   Medium accuracy, medium cost
  │ ◆     Low accuracy, low cost
  └─────────────────────────► Speed
```

Each point (◆) represents a different prompt variant optimized for different trade-offs.

### Evolutionary Loop

GEPA follows a four-step cycle:

1. **Sample**: Evaluate prompt variants on test inputs
2. **Reflect**: Use the LLM to analyze what went wrong or could improve
3. **Mutate**: Generate new prompt variations based on reflection
4. **Select**: Choose the best candidates for the next generation

### Key Components

| Component | Purpose |
|-----------|---------|
| **Population** | Set of prompt candidates being optimized |
| **Evaluation** | Measures prompt quality across multiple objectives |
| **Selection** | Chooses parents for breeding based on Pareto dominance |
| **Mutation** | Makes small changes to prompts (word changes, instruction tweaks) |
| **Crossover** | Combines elements from multiple parent prompts |
| **Convergence Detection** | Determines when optimization has plateaued |

---

## When to Use GEPA

### Ideal Use Cases

GEPA excels when:

- **Multiple Objectives Matter**: You need to balance accuracy, speed, cost, or other metrics
- **Quality is Critical**: The cost of optimization is justified by improved prompt quality
- **Iterative Improvement**: You're refining prompts over time with new requirements
- **Complex Tasks**: Multi-step reasoning, instruction following, or nuanced tasks
- **Trade-off Analysis**: You need to understand trade-offs between competing goals

### When NOT to Use GEPA

Consider alternatives when:

- **Single Simple Prompt**: Basic tasks with obvious prompts don't need optimization
- **Time Constraints**: Optimization requires multiple LLM calls and takes time
- **Budget Limits**: Each optimization run costs money (see Cost Management)
- **Static Requirements**: Prompts won't change or don't need improvement
- **No Evaluation Metrics**: You can't define clear objectives to optimize

### Cost Considerations

⚠️ **GEPA MAKES REAL API CALLS AND INCURS COSTS**

- Each generation evaluates 10-20 prompts
- Each evaluation typically requires 1-5 LLM calls
- Default 10 generations = 100-1000 API calls
- Estimated cost: $0.50 - $10+ per optimization run

Always start with small population sizes and cheaper models for testing.

---

## Getting Started

### Prerequisites

1. **Install Dependencies**: Ensure Jido AI is installed
2. **Set API Keys**: Configure provider credentials
3. **Define Test Inputs**: Prepare evaluation data

### Basic Setup

```elixir
# Set your API key
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Define test inputs for evaluation
test_inputs = [
  "Classify sentiment: I love this product!",
  "Classify sentiment: This is terrible.",
  "Classify sentiment: It's okay, nothing special."
]

# Run optimization
{:ok, result} = Examples.WorkingGEPAExample.optimize_prompt(
  model: "openai:gpt-3.5-turbo",
  initial_prompt: "Classify the sentiment of the following text as positive, negative, or neutral: {{input}}",
  test_inputs: test_inputs,
  population_size: 10,
  generations: 5,
  objectives: [:accuracy, :latency, :cost]
)

# Examine results
IO.inspect(result.best_prompt)
IO.inspect(result.pareto_frontier)
```

### Model Format

Models **must** be specified in the format: `"provider:model_name"`

Supported providers (via ReqLLM):
- `"openai:gpt-4"` - OpenAI GPT-4
- `"openai:gpt-3.5-turbo"` - OpenAI GPT-3.5 Turbo
- `"anthropic:claude-3-sonnet-20240229"` - Anthropic Claude 3 Sonnet
- `"anthropic:claude-3-haiku-20240307"` - Anthropic Claude 3 Haiku
- `"groq:llama-3.1-8b-instant"` - Groq Llama 3.1
- And 50+ more via ReqLLM

See [ReqLLM documentation](https://hexdocs.pm/req_llm) for the full provider list.

### Simple Example

```elixir
defmodule MyPromptOptimizer do
  def optimize_classification_prompt do
    # Test data
    test_cases = [
      %{input: "I love Elixir!", expected: "positive"},
      %{input: "This bug is frustrating.", expected: "negative"},
      %{input: "The documentation is adequate.", expected: "neutral"}
    ]

    # Initial prompt template
    initial_prompt = """
    Classify the sentiment of this text: {{input}}
    Return only: positive, negative, or neutral
    """

    # Run GEPA optimization
    {:ok, result} = Examples.WorkingGEPAExample.optimize_prompt(
      model: "openai:gpt-3.5-turbo",
      initial_prompt: initial_prompt,
      test_inputs: Enum.map(test_cases, & &1.input),
      population_size: 8,
      generations: 3,
      max_cost: 1.0  # Budget limit: $1
    )

    IO.puts("Optimized prompt:")
    IO.puts(result.best_prompt)

    IO.puts("\nFitness scores:")
    IO.inspect(result.best_fitness)
  end
end
```

---

## Understanding GEPA Components

### Population Management

The population is the set of prompt candidates being optimized:

```elixir
# Population structure
%{
  solutions: [
    %{
      prompt: "Your optimized prompt text...",
      fitness: %{accuracy: 0.95, latency: 120, cost: 0.002},
      objectives: [:accuracy, :latency, :cost]
    },
    # ... more solutions
  ],
  generation: 5,
  best_solution: %{...}
}
```

**Population Size**: Controls diversity vs. convergence speed
- Small (5-10): Faster convergence, less diversity
- Medium (10-20): Good balance (recommended)
- Large (20-50): More diversity, slower, more expensive

### Selection Strategies

GEPA uses Pareto-based selection to choose parent prompts:

```elixir
# Selection methods
selection_methods = [
  :pareto_tournament,      # Tournament selection using dominance
  :crowding_distance,      # Prefer diverse solutions
  :hypervolume_contribution # Maximize covered objective space
]
```

**Pareto Dominance**: Solution A dominates solution B if A is better or equal on all objectives and strictly better on at least one.

### Mutation Operators

Mutations introduce variation by modifying prompts:

| Mutation Type | Effect | Example |
|---------------|--------|---------|
| **Instruction Modifier** | Add/modify instructions | "Be concise" → "Be concise and specific" |
| **Wording Tweak** | Rephrase for clarity | "Analyze this" → "Carefully examine this" |
| **Format Adjuster** | Change output format | "Respond..." → "Respond in JSON format" |
| **Example Addition** | Add few-shot examples | Add "Example: input → output" |
| **Constraint Addition** | Add guardrails | "Avoid technical jargon" |

**Mutation Rate**: Probability of applying each mutation (default: 0.3)

### Crossover Operators

Crossover combines elements from multiple parent prompts:

```elixir
# Parent prompts
parent1 = "Analyze the sentiment. Be concise."
parent2 = "Classify the emotion. Provide reasoning."

# Crossover result (combines elements)
offspring = "Analyze the sentiment. Provide reasoning."
```

**Crossover Rate**: Probability of breeding vs. mutation (default: 0.5)

### Convergence Detection

GEPA automatically detects when optimization has plateaued:

```elixir
# Convergence triggers
convergence_criteria = [
  plateau_detection: true,    # No improvement for N generations
  max_generations: 10,        # Hard limit
  target_fitness: 0.95,       # Stop when goal reached
  budget_exhausted: true      # Stop when cost limit hit
]
```

---

## Multi-Objective Optimization

### Defining Objectives

Objectives are metrics you want to optimize:

```elixir
# Common objectives
objectives = [
  :accuracy,      # Correctness of outputs
  :latency,       # Response time (lower is better)
  :cost,          # API costs (lower is better)
  :robustness,    # Consistency across inputs
  :conciseness,   # Output brevity
  :completeness   # Output thoroughness
]
```

### Objective Functions

Each objective needs a function to measure it:

```elixir
# Accuracy: Compare output to expected result
def calculate_accuracy(outputs, expected) do
  correct = Enum.count(outputs, fn %{output: output, expected: exp} ->
    String.contains?(String.downcase(output), String.downcase(exp))
  end)
  correct / length(outputs)
end

# Latency: Average response time
def calculate_latency(outputs) do
  total = Enum.sum(outputs, & &1.latency)
  total / length(outputs)
end

# Cost: Sum of API costs
def calculate_cost(outputs) do
  Enum.sum(outputs, & &1.cost)
end
```

### Objective Weights

Balance the importance of different objectives:

```elixir
# Equal weight (default)
objective_weights = %{
  accuracy: 1.0,
  latency: 1.0,
  cost: 1.0
}

# Prioritize accuracy
objective_weights = %{
  accuracy: 2.0,    # 2× weight
  latency: 1.0,
  cost: 0.5         # Half weight
}
```

### Trade-off Analysis

Examine the Pareto frontier to understand trade-offs:

```elixir
# After optimization
result.pareto_frontier
|> Enum.each(fn solution ->
  IO.puts """
  Prompt: #{String.slice(solution.prompt, 0, 50)}...
  Accuracy: #{solution.fitness.accuracy}
  Latency: #{solution.fitness.latency}ms
  Cost: $#{solution.fitness.cost}
  """
end)
```

### Selecting from the Frontier

Choose the solution that best fits your needs:

```elixir
# Highest accuracy
best_accuracy = Enum.max_by(frontier, & &1.fitness.accuracy)

# Lowest cost
cheapest = Enum.min_by(frontier, & &1.fitness.cost)

# Balanced (closest to ideal point)
balanced = find_balanced_solution(frontier, %{
  accuracy: 0.9,
  latency: 100,
  cost: 0.001
})
```

---

## Configuration Options

### Core Parameters

```elixir
config = %{
  # Model configuration
  model: "openai:gpt-3.5-turbo",

  # Initial prompt
  initial_prompt: "Your starting prompt template",

  # Test data
  test_inputs: ["input1", "input2", "input3"],

  # Population settings
  population_size: 15,          # Number of candidates per generation
  generations: 10,              # Maximum generations

  # Evolutionary operators
  mutation_rate: 0.3,           # Probability of mutation (0.0-1.0)
  crossover_rate: 0.5,          # Probability of crossover (0.0-1.0)

  # Objectives
  objectives: [:accuracy, :latency, :cost],
  objective_weights: %{         # Optional weights
    accuracy: 1.0,
    latency: 1.0,
    cost: 1.0
  },

  # Budget limits
  max_cost: 5.0,                # Maximum spend in dollars
  max_time: 600_000,            # Maximum time in milliseconds

  # Convergence
  patience: 3,                  # Generations without improvement
  min_improvement: 0.01,        # Minimum fitness improvement

  # Logging
  verbose: true,                # Detailed progress logging
  log_frequency: 1              # Log every N generations
}
```

### LLM Parameters

Fine-tune the LLM behavior during evaluation:

```elixir
llm_params = %{
  temperature: 0.7,             # Randomness (0.0-1.0)
  max_tokens: 500,              # Maximum response length
  top_p: 0.9,                   # Nucleus sampling
  frequency_penalty: 0.0,       # Penalize repetition
  presence_penalty: 0.0,        # Encourage new topics
  timeout: 30_000               # Request timeout (ms)
}
```

### Advanced Options

```elixir
advanced = %{
  # Parallel evaluation
  max_concurrent: 5,            # Max concurrent LLM calls

  # Selection strategy
  selection_method: :pareto_tournament,
  tournament_size: 3,

  # Mutation strategies
  mutation_operators: [
    :instruction_modifier,
    :wording_tweak,
    :format_adjuster
  ],

  # Archive elite solutions
  archive_size: 10,             # Keep top N solutions

  # Diversity maintenance
  diversity_threshold: 0.7,     # Minimum prompt similarity

  # Early stopping
  target_fitness: 0.95,         # Stop when reached

  # Checkpointing
  checkpoint_frequency: 5,      # Save every N generations
  checkpoint_dir: "/tmp/gepa"
}
```

---

## Working with LLM Providers

### Setting API Keys

GEPA uses the Jido.AI.Keyring for secure credential management:

```elixir
# OpenAI
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Anthropic
Jido.AI.Keyring.set_env_value(:anthropic_api_key, "sk-ant-...")

# Groq
Jido.AI.Keyring.set_env_value(:groq_api_key, "gsk_...")

# Verify key is set
case Jido.AI.Keyring.get_env_value(:openai_api_key, nil) do
  nil -> IO.puts("Key not set!")
  key -> IO.puts("Key configured: #{String.slice(key, 0, 7)}...")
end
```

### Provider-Specific Features

Different providers have different capabilities:

```elixir
# Anthropic - Long context, accurate reasoning
%{
  model: "anthropic:claude-3-sonnet-20240229",
  max_tokens: 4096,  # Claude supports longer outputs
  temperature: 0.7
}

# OpenAI - Fast, cost-effective
%{
  model: "openai:gpt-3.5-turbo",
  max_tokens: 1000,
  temperature: 0.7
}

# Groq - Ultra-fast inference
%{
  model: "groq:llama-3.1-8b-instant",
  max_tokens: 500,
  temperature: 0.7
}
```

### Provider Selection Strategy

Choose providers based on your needs:

| Provider | Best For | Cost | Speed |
|----------|----------|------|-------|
| **OpenAI GPT-3.5** | General purpose, cost-effective | $ | Fast |
| **OpenAI GPT-4** | High accuracy, complex tasks | $$$ | Medium |
| **Anthropic Claude Haiku** | Fast, cheap, good quality | $ | Fast |
| **Anthropic Claude Sonnet** | Balanced quality and cost | $$ | Medium |
| **Anthropic Claude Opus** | Highest quality | $$$$ | Slow |
| **Groq Llama** | Ultra-fast inference | $ | Very Fast |

### Error Handling

Handle provider errors gracefully:

```elixir
case Examples.WorkingGEPAExample.optimize_prompt(config) do
  {:ok, result} ->
    # Success
    handle_results(result)

  {:error, "API key not found" <> _} ->
    IO.puts("Error: API key not configured for provider")
    IO.puts("Set with: Jido.AI.Keyring.set_env_value(:provider_api_key, \"key\")")

  {:error, "Rate limit" <> _} ->
    IO.puts("Error: Rate limit exceeded")
    IO.puts("Wait and retry, or use a different provider")

  {:error, "Budget exceeded" <> _} ->
    IO.puts("Error: Cost budget exhausted")
    IO.puts("Increase max_cost or reduce population_size/generations")

  {:error, reason} ->
    IO.puts("Error: #{reason}")
end
```

---

## Cost Management

### ⚠️ CRITICAL: Understanding Costs

**GEPA MAKES REAL API CALLS AND INCURS ACTUAL COSTS**

Every optimization run involves:
- **Population size** × **Generations** = Total evaluations
- Each evaluation = 1-5 LLM API calls
- Costs vary by provider, model, and prompt length

**Example Cost Calculation:**
```
Population: 15 prompts
Generations: 10
Total evaluations: 150 prompts minimum

At $0.002 per evaluation (GPT-3.5):
Estimated cost: $0.30

At $0.03 per evaluation (GPT-4):
Estimated cost: $4.50
```

### Budget Limits

Always set a budget limit:

```elixir
config = %{
  # ... other config
  max_cost: 2.0,  # Stop after $2.00 spent

  # Also set time limit
  max_time: 600_000,  # 10 minutes maximum
}
```

### Cost Tracking

Monitor spending during optimization:

```elixir
# Enable verbose logging
config = %{verbose: true, ...}

# Watch the console output:
# Generation 1/10: Best fitness 0.75, Cost so far: $0.15
# Generation 2/10: Best fitness 0.82, Cost so far: $0.31
# ...

# After completion
IO.puts("Total cost: $#{result.total_cost}")
IO.puts("Total evaluations: #{result.total_evaluations}")
IO.puts("Cost per evaluation: $#{result.total_cost / result.total_evaluations}")
```

### Cost Reduction Strategies

Minimize costs while optimizing:

1. **Start Small**: Use small populations (5-10) and few generations (3-5) for testing

```elixir
# Development/testing configuration
dev_config = %{
  population_size: 5,
  generations: 3,
  max_cost: 0.50
}
```

2. **Use Cheaper Models**: Start with GPT-3.5 or Claude Haiku

```elixir
# Cheap models for development
cheap_models = [
  "openai:gpt-3.5-turbo",
  "anthropic:claude-3-haiku-20240307",
  "groq:llama-3.1-8b-instant"
]
```

3. **Limit Test Inputs**: Use fewer evaluation examples

```elixir
# Development: 3-5 inputs
test_inputs = ["input1", "input2", "input3"]

# Production: 10-20 inputs
# test_inputs = generate_comprehensive_test_set()
```

4. **Batch Operations**: Evaluate multiple inputs per LLM call when possible

5. **Progressive Optimization**: Start cheap, then refine with better models

```elixir
# Phase 1: Quick optimization with cheap model
{:ok, phase1} = optimize_prompt(%{model: "openai:gpt-3.5-turbo", ...})

# Phase 2: Refine best prompt with better model
{:ok, phase2} = optimize_prompt(%{
  model: "anthropic:claude-3-sonnet-20240229",
  initial_prompt: phase1.best_prompt,
  generations: 3
})
```

### Provider Account Limits

Set limits in your provider accounts:

- **OpenAI**: Set monthly budget limits in account settings
- **Anthropic**: Configure usage notifications
- **All Providers**: Monitor usage dashboards regularly

---

## Best Practices

### 1. Define Clear Objectives

```elixir
# Good: Specific, measurable objectives
objectives = [:accuracy, :latency, :cost]

# Bad: Vague or unmeasurable
# objectives = [:quality, :goodness]
```

### 2. Use Representative Test Data

```elixir
# Good: Diverse, representative inputs
test_inputs = [
  "Simple case",
  "Complex scenario with multiple clauses",
  "Edge case: empty input",
  "Edge case: very long text...",
  "Ambiguous input that could be interpreted multiple ways"
]

# Bad: Too similar or not representative
# test_inputs = ["test", "test2", "test3"]
```

### 3. Start with Simple Baselines

```elixir
# Start with a basic prompt
initial_prompt = "Classify the sentiment: {{input}}"

# Let GEPA evolve it
# Don't start with over-engineered prompts
```

### 4. Iterate Progressively

```elixir
# Phase 1: Quick exploration
phase1 = optimize(%{population: 8, generations: 3})

# Phase 2: Refine top candidates
phase2 = optimize(%{
  initial_prompt: phase1.best_prompt,
  population: 15,
  generations: 10
})
```

### 5. Monitor and Validate

```elixir
# After optimization, validate on held-out test set
validation_inputs = load_validation_data()
results = evaluate_prompt(optimized_prompt, validation_inputs)

# Check for overfitting
if results.accuracy < training_accuracy - 0.1 do
  IO.puts("Warning: Possible overfitting")
end
```

### 6. Save and Version Prompts

```elixir
# Save optimization results
File.write!("prompts/sentiment_v1.txt", result.best_prompt)

# Save metadata
metadata = %{
  version: "1.0",
  date: Date.utc_today(),
  fitness: result.best_fitness,
  config: config
}
File.write!("prompts/sentiment_v1_meta.json", Jason.encode!(metadata))
```

### 7. Use Appropriate Models

```elixir
# For development/testing
dev_model = "openai:gpt-3.5-turbo"

# For production optimization
prod_model = "anthropic:claude-3-sonnet-20240229"

# Match your production model
# Don't optimize with GPT-3.5 if you'll use GPT-4 in production
```

### 8. Balance Objectives

```elixir
# Don't over-optimize for one objective
# This might sacrifice too much on others
objective_weights = %{
  accuracy: 2.0,    # Important but not overwhelming
  latency: 1.0,
  cost: 1.0
}

# Not: accuracy: 10.0 (would ignore other objectives)
```

### 9. Document Your Process

```elixir
# Keep notes on what works
"""
Optimization Run: Sentiment Classification v3
Date: 2024-10-29
Config: population=15, generations=10
Model: gpt-3.5-turbo
Results:
  - Accuracy improved from 0.75 to 0.89
  - Cost increased from $0.001 to $0.002 per call
  - Latency decreased from 350ms to 280ms
Notes:
  - Adding "Think step-by-step" improved accuracy significantly
  - Shorter instructions reduced latency without hurting quality
"""
```

### 10. Respect Budget Constraints

```elixir
# Always set limits
config = %{
  max_cost: 5.0,           # Hard limit
  max_time: 600_000,       # Timeout
  target_fitness: 0.95     # Stop when good enough
}

# Monitor during optimization
# Don't run unbounded experiments
```

---

## Example Workflow

Here's a complete workflow for optimizing a sentiment classification prompt:

```elixir
defmodule SentimentOptimization do
  @moduledoc """
  Complete workflow for optimizing a sentiment classification prompt with GEPA.
  """

  alias Examples.WorkingGEPAExample
  alias Jido.AI.Keyring

  def run do
    # Step 1: Setup
    IO.puts("=== Step 1: Setup ===")
    setup_api_keys()

    # Step 2: Prepare test data
    IO.puts("\n=== Step 2: Prepare Test Data ===")
    test_inputs = prepare_test_data()
    IO.puts("Prepared #{length(test_inputs)} test inputs")

    # Step 3: Define objectives
    IO.puts("\n=== Step 3: Define Objectives ===")
    objectives = [:accuracy, :latency, :cost]
    IO.puts("Optimizing for: #{inspect(objectives)}")

    # Step 4: Initial baseline
    IO.puts("\n=== Step 4: Baseline Evaluation ===")
    baseline_prompt = """
    Classify the sentiment of the following text as positive, negative, or neutral.

    Text: {{input}}

    Sentiment:
    """
    baseline_results = evaluate_baseline(baseline_prompt, test_inputs)
    IO.puts("Baseline accuracy: #{baseline_results.accuracy}")

    # Step 5: Quick exploration (cheap model, small population)
    IO.puts("\n=== Step 5: Quick Exploration ===")
    {:ok, phase1} = WorkingGEPAExample.optimize_prompt(
      model: "openai:gpt-3.5-turbo",
      initial_prompt: baseline_prompt,
      test_inputs: test_inputs,
      population_size: 8,
      generations: 3,
      objectives: objectives,
      max_cost: 0.50,
      verbose: true
    )

    IO.puts("\nPhase 1 Results:")
    IO.puts("Best accuracy: #{phase1.best_fitness.accuracy}")
    IO.puts("Cost: $#{phase1.total_cost}")
    IO.puts("Improvement: #{(phase1.best_fitness.accuracy - baseline_results.accuracy) * 100}%")

    # Step 6: Detailed optimization (larger population, more generations)
    IO.puts("\n=== Step 6: Detailed Optimization ===")
    {:ok, phase2} = WorkingGEPAExample.optimize_prompt(
      model: "openai:gpt-3.5-turbo",
      initial_prompt: phase1.best_prompt,
      test_inputs: test_inputs,
      population_size: 15,
      generations: 10,
      objectives: objectives,
      max_cost: 2.0,
      verbose: true
    )

    IO.puts("\nPhase 2 Results:")
    IO.puts("Best accuracy: #{phase2.best_fitness.accuracy}")
    IO.puts("Cost: $#{phase2.total_cost}")

    # Step 7: Analyze Pareto frontier
    IO.puts("\n=== Step 7: Analyze Trade-offs ===")
    analyze_frontier(phase2.pareto_frontier)

    # Step 8: Validate on held-out data
    IO.puts("\n=== Step 8: Validation ===")
    validation_data = prepare_validation_data()
    validation_results = validate_prompt(phase2.best_prompt, validation_data)
    IO.puts("Validation accuracy: #{validation_results.accuracy}")

    # Step 9: Save results
    IO.puts("\n=== Step 9: Save Results ===")
    save_results(phase2, validation_results)

    # Step 10: Summary
    IO.puts("\n=== Summary ===")
    print_summary(baseline_results, phase2, validation_results)

    {:ok, phase2}
  end

  defp setup_api_keys do
    case Keyring.get_env_value(:openai_api_key, nil) do
      nil ->
        raise "OpenAI API key not set. Run: Jido.AI.Keyring.set_env_value(:openai_api_key, \"sk-...\")"
      key ->
        IO.puts("API key configured: #{String.slice(key, 0, 7)}...")
    end
  end

  defp prepare_test_data do
    [
      "I absolutely love this product! It exceeded all my expectations.",
      "This is the worst experience I've ever had. Completely disappointed.",
      "It's okay, nothing special but gets the job done.",
      "Horrible customer service and poor quality. Would not recommend.",
      "Amazing! Best purchase I've made this year. Highly recommend!",
      "Not bad, not great. Just average overall.",
      "Fantastic quality and fast shipping. Very satisfied!",
      "Terrible. Complete waste of money and time."
    ]
  end

  defp prepare_validation_data do
    [
      "Excellent product, will buy again!",
      "Very disappointed with the quality.",
      "It's decent for the price.",
      "Outstanding service and support!"
    ]
  end

  defp evaluate_baseline(prompt, test_inputs) do
    # Simulate baseline evaluation
    # In real implementation, would call LLM
    %{accuracy: 0.75, latency: 350, cost: 0.001}
  end

  defp validate_prompt(prompt, validation_data) do
    # Simulate validation
    # In real implementation, would evaluate on validation set
    %{accuracy: 0.88, latency: 280, cost: 0.002}
  end

  defp analyze_frontier(frontier) do
    IO.puts("\nPareto Frontier Solutions:")
    frontier
    |> Enum.with_index(1)
    |> Enum.each(fn {solution, idx} ->
      IO.puts("\nSolution #{idx}:")
      IO.puts("  Accuracy: #{Float.round(solution.fitness.accuracy, 3)}")
      IO.puts("  Latency: #{round(solution.fitness.latency)}ms")
      IO.puts("  Cost: $#{Float.round(solution.fitness.cost, 4)}")
      IO.puts("  Prompt preview: #{String.slice(solution.prompt, 0, 60)}...")
    end)
  end

  defp save_results(optimization_result, validation_result) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()

    # Save best prompt
    File.mkdir_p!("prompts")
    File.write!("prompts/sentiment_optimized.txt", optimization_result.best_prompt)

    # Save metadata
    metadata = %{
      timestamp: timestamp,
      optimization: %{
        best_fitness: optimization_result.best_fitness,
        total_cost: optimization_result.total_cost,
        generations: optimization_result.generation
      },
      validation: validation_result
    }

    File.write!("prompts/sentiment_optimized_meta.json",
                Jason.encode!(metadata, pretty: true))

    IO.puts("Saved results to prompts/")
  end

  defp print_summary(baseline, optimization, validation) do
    IO.puts("""

    Optimization Complete!
    =====================

    Baseline Accuracy:    #{Float.round(baseline.accuracy, 3)}
    Optimized Accuracy:   #{Float.round(optimization.best_fitness.accuracy, 3)}
    Validation Accuracy:  #{Float.round(validation.accuracy, 3)}

    Improvement:          #{Float.round((optimization.best_fitness.accuracy - baseline.accuracy) * 100, 1)}%
    Total Cost:           $#{Float.round(optimization.total_cost, 2)}
    Generations:          #{optimization.generation}

    Next Steps:
    1. Review the optimized prompt in prompts/sentiment_optimized.txt
    2. Test on additional validation data
    3. Deploy to production if results are satisfactory
    """)
  end
end

# Run the workflow
SentimentOptimization.run()
```

### Running the Workflow

```elixir
# In IEx
iex> c "sentiment_optimization.ex"
iex> SentimentOptimization.run()
```

---

## Troubleshooting

### Common Issues

#### API Key Not Found

**Problem**: `{:error, "API key not found: OPENAI_API_KEY"}`

**Solution**:
```elixir
# Set the key for your provider
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Verify it's set
Jido.AI.Keyring.get_env_value(:openai_api_key, nil)
```

#### Budget Exceeded

**Problem**: Optimization stops early with "Budget exceeded"

**Solutions**:
```elixir
# Increase budget
config = %{max_cost: 10.0}  # Was 5.0

# Or reduce population/generations
config = %{
  population_size: 10,  # Was 20
  generations: 5        # Was 10
}
```

#### Poor Convergence

**Problem**: Fitness doesn't improve over generations

**Solutions**:
```elixir
# 1. Increase mutation rate
config = %{mutation_rate: 0.5}  # Was 0.3

# 2. Increase population diversity
config = %{population_size: 20}  # Was 10

# 3. Better initial prompt
config = %{
  initial_prompt: "A more detailed and specific starting prompt..."
}

# 4. More test inputs for evaluation
test_inputs = generate_diverse_test_set(count: 15)  # Was 5
```

#### Evaluation Errors

**Problem**: Errors during prompt evaluation

**Solutions**:
```elixir
# 1. Check test input format
test_inputs = [
  "Valid string input",
  "Another valid input"
]
# Not: [%{complex: "structure"}]

# 2. Verify prompt template syntax
# Good: "Classify: {{input}}"
# Bad: "Classify: {input}"  # Wrong placeholder syntax

# 3. Check model availability
# Some models may not be available in your region
```

#### Rate Limiting

**Problem**: API rate limit errors

**Solutions**:
```elixir
# 1. Reduce concurrent calls
config = %{max_concurrent: 2}  # Was 5

# 2. Add delays between requests
config = %{request_delay: 1000}  # 1 second

# 3. Use a different provider
config = %{model: "groq:llama-3.1-8b-instant"}  # Faster limits
```

#### Memory Issues

**Problem**: Out of memory with large populations

**Solutions**:
```elixir
# 1. Reduce population size
config = %{population_size: 10}  # Was 50

# 2. Limit archive size
config = %{archive_size: 5}  # Was 20

# 3. Clear history periodically
config = %{clear_history_every: 5}  # Every 5 generations
```

### Debugging Tips

1. **Enable Verbose Logging**
```elixir
config = %{verbose: true}
# Shows detailed progress and fitness values
```

2. **Save Checkpoints**
```elixir
config = %{
  checkpoint_frequency: 2,
  checkpoint_dir: "/tmp/gepa_debug"
}
# Review state if optimization fails
```

3. **Test Individual Components**
```elixir
# Test evaluation function
result = evaluate_single_prompt(prompt, test_inputs[0])
IO.inspect(result)

# Test mutation
mutated = mutate_prompt(prompt, mutation_rate: 0.3)
IO.inspect(mutated)
```

4. **Validate Test Data**
```elixir
# Ensure test inputs are valid
test_inputs
|> Enum.each(fn input ->
  unless is_binary(input) and String.length(input) > 0 do
    raise "Invalid test input: #{inspect(input)}"
  end
end)
```

### Getting Help

If you encounter issues:

1. Check the [examples](../examples/) for working code
2. Review the [API documentation](https://hexdocs.pm/jido_ai)
3. Search [GitHub issues](https://github.com/agentjido/jido_ai/issues)
4. Ask in the [Elixir Forum](https://elixirforum.com/)

---

## Conclusion

GEPA brings powerful evolutionary optimization to prompt engineering, leveraging Elixir's concurrency and fault tolerance for efficient, parallel evaluation. By optimizing across multiple objectives simultaneously, GEPA helps you find prompts that balance accuracy, speed, cost, and other metrics according to your specific needs.

### Key Takeaways

- **Multi-Objective**: Optimize for multiple competing goals simultaneously
- **Sample Efficient**: Achieve results with far fewer evaluations than traditional methods
- **Cost Aware**: Built-in budget limits and cost tracking
- **Pareto Frontier**: Maintain diverse solutions representing different trade-offs
- **LLM-Guided**: Use the AI itself to propose improvements through reflection

### Next Steps

1. **Start Simple**: Begin with small populations and cheap models
2. **Define Clear Objectives**: Know what you're optimizing for
3. **Iterate**: Use progressive refinement for best results
4. **Monitor Costs**: Always set budget limits
5. **Validate**: Test optimized prompts on held-out data

### Further Reading

- [Prompt Engineering Guide](./prompt.md)
- [Actions Guide](./actions.md)
- [Provider Configuration](./providers.md)
- [GEPA Research Paper](https://arxiv.org/abs/2507.19457)
- [ReqLLM Documentation](https://hexdocs.pm/req_llm)

### Examples

Check out the complete working examples:

- `examples/gepa_optimization_example.ex` - API demonstration
- `examples/working_gepa_example.ex` - Full working implementation
- `examples/chain_of_thought_example.ex` - CoT reasoning patterns
- `examples/tree_of_thought_example.ex` - ToT exploration patterns

By mastering GEPA, you can systematically improve your prompts, understand trade-offs between competing objectives, and build more effective AI-powered applications with confidence in your prompt quality.
