# Running GEPA with Local LLMs

## Overview

This guide shows you how to run GEPA (Genetic-Pareto Prompt Optimization) with local LLM models instead of cloud-based APIs. Using local models eliminates API costs, provides complete privacy, and removes rate limits.

### Key Benefits

- **Zero API Costs**: Run unlimited optimizations without spending money
- **Complete Privacy**: Your data never leaves your machine
- **No Rate Limits**: Optimize as much as you want
- **Fast Iteration**: No network latency for quick experiments
- **Offline Capable**: Works without internet connection

### Tradeoffs

- **Hardware Requirements**: Requires sufficient RAM and disk space (4-70GB per model)
- **Slower Inference**: Local models are typically slower than cloud APIs
- **Quality Variance**: Quality depends on the model and your hardware
- **Setup Required**: Need to install and configure local LLM runtime

---

## Prerequisites

### Supported Local LLM Runtimes

GEPA supports local LLMs through [ReqLLM](https://hexdocs.pm/req_llm)'s provider system:

- **Ollama** (Recommended) - Easy to install and use
- **LM Studio** - GUI-based with OpenAI-compatible API
- **LocalAI** - OpenAI-compatible local server
- **vLLM** - High-performance inference server

This guide focuses on **Ollama** as it's the most popular and easiest to set up.

### Installing Ollama

**macOS / Linux:**
```bash
# Quick install
curl -fsSL https://ollama.com/install.sh | sh

# Or download from: https://ollama.ai/download
```

**Windows:**
- Download installer from [ollama.ai/download](https://ollama.ai/download)

**Verify Installation:**
```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Should return JSON with available models
```

### Downloading Models

Pull models before using them:

```bash
# Recommended for general use
ollama pull llama3.1:8b        # 4.7GB, good balance

# Other popular models
ollama pull mistral            # 4.1GB, fast
ollama pull phi3               # 2.3GB, very fast, lightweight
ollama pull codellama          # 3.8GB, best for code generation
ollama pull llama3.1:70b       # 40GB, highest quality (requires 64GB+ RAM)

# List installed models
ollama list
```

---

## Basic Usage

### Simple IEx Session

Start IEx and run a basic GEPA optimization with a local model:

```elixir
# Start IEx
iex -S mix

# Create agent
agent = %{
  id: "local-optimizer",
  name: "Local LLM Optimizer",
  state: %{},
  pending_instructions: :queue.new(),
  actions: [],
  runner: Jido.AI.Runner.GEPA,
  result: nil
}

# Run optimization with local Ollama model
{:ok, updated_agent, directives} = Jido.AI.Runner.GEPA.run(
  agent,
  test_inputs: ["The weather is nice today", "This is frustrating"],
  seed_prompts: ["Classify sentiment: {{input}}"],
  model: "ollama:llama3.1",  # ← Local model via Ollama
  population_size: 5,
  max_generations: 3,
  objectives: [:accuracy, :latency]
)

# View results
best_prompts = updated_agent.state.gepa_best_prompts
IO.puts("Best prompt: #{hd(best_prompts).prompt}")
IO.puts("Fitness: #{hd(best_prompts).fitness}")
```

### Model Format

Local models use the same `"provider:model"` format as cloud APIs:

```elixir
# Ollama models
model: "ollama:llama3.1"      # Default llama3.1:latest
model: "ollama:llama3.1:8b"   # Specific tag
model: "ollama:mistral"
model: "ollama:codellama"
model: "ollama:phi3"

# LM Studio (if running)
model: "lmstudio:your-model-name"

# Custom OpenAI-compatible server
model: "openai:model-name"    # Configure base_url separately
```

---

## Complete Example Module

Here's a complete module you can copy-paste into IEx:

```elixir
defmodule LocalGEPAExample do
  @moduledoc """
  Example of running GEPA with local LLM models.
  """

  alias Jido.AI.Runner.GEPA

  def run_simple_test do
    IO.puts("🚀 Starting GEPA with local Ollama model...")

    agent = build_agent()

    {:ok, result, _directives} = GEPA.run(
      agent,
      test_inputs: ["The product works great!", "This is terrible."],
      seed_prompts: ["Analyze sentiment: {{input}}"],
      model: "ollama:llama3.1",
      population_size: 5,
      max_generations: 3,
      objectives: [:accuracy, :latency]
    )

    display_results(result)
  end

  def run_code_generation do
    IO.puts("🚀 Code generation with local CodeLlama...")

    agent = build_agent()

    task = %{
      type: :code_generation,
      language: :elixir,
      problem: "Calculate fibonacci numbers",
      test_cases: [
        %{input: 0, expected: 0},
        %{input: 5, expected: 5},
        %{input: 10, expected: 55}
      ]
    }

    {:ok, result, _} = GEPA.run(
      agent,
      test_inputs: ["fibonacci(5)", "fibonacci(10)"],
      seed_prompts: ["Write Elixir code to {{input}}"],
      model: "ollama:codellama",  # Use CodeLlama for code
      task: task,
      population_size: 5,
      max_generations: 3,
      objectives: [:accuracy, :cost]
    )

    display_results(result)
  end

  defp build_agent do
    %{
      id: "local-test-#{System.unique_integer([:positive])}",
      name: "Local LLM Test",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: GEPA,
      result: nil
    }
  end

  defp display_results(agent) do
    best_prompts = agent.state.gepa_best_prompts || []
    pareto_frontier = agent.state.gepa_pareto_frontier || []

    IO.puts("\n📊 Results:")
    IO.puts("  Best prompts: #{length(best_prompts)}")
    IO.puts("  Pareto frontier: #{length(pareto_frontier)}")

    if best_prompts != [] do
      best = hd(best_prompts)
      IO.puts("\n🏆 Best prompt:")
      IO.puts("  #{best.prompt}")
      IO.puts("  Fitness: #{Float.round(best.fitness, 3)}")
    end

    if pareto_frontier != [] do
      IO.puts("\n🎯 Pareto frontier:")
      Enum.with_index(pareto_frontier, 1)
      |> Enum.each(fn {candidate, idx} ->
        IO.puts("  #{idx}. Fitness: #{Float.round(candidate.fitness, 3)}")
        IO.puts("     Prompt: #{String.slice(candidate.prompt, 0..60)}...")
      end)
    end

    :ok
  end
end

# Run it:
# LocalGEPAExample.run_simple_test()
# LocalGEPAExample.run_code_generation()
```

---

## Model Selection Guide

Choose the right local model for your use case:

| Model | Size | Speed | Quality | RAM Needed | Best For |
|-------|------|-------|---------|------------|----------|
| **phi3** | 2.3GB | Very Fast | Good | 8GB | Quick experiments, testing |
| **mistral** | 4.1GB | Fast | Good | 8GB | Fast iterations |
| **llama3.1:8b** | 4.7GB | Fast | Very Good | 8GB | General purpose, balanced |
| **codellama** | 3.8GB | Fast | Very Good | 8GB | Code generation tasks |
| **llama3.1:70b** | 40GB | Slow | Excellent | 64GB+ | Production quality |

### Recommendations by Task

```elixir
# Quick testing and development
model: "ollama:phi3"

# General sentiment/classification
model: "ollama:llama3.1"

# Code generation
model: "ollama:codellama"

# Best quality (if you have the RAM)
model: "ollama:llama3.1:70b"

# Fastest iterations
model: "ollama:mistral"
```

---

## Configuration Tips

### Adjust Population and Generations for Speed

Local models are slower, so reduce these for faster results:

```elixir
# For cloud APIs (fast)
GEPA.run(agent,
  population_size: 20,
  max_generations: 10,
  # ...
)

# For local LLMs (slower) - reduce both
GEPA.run(agent,
  population_size: 5,   # ← Smaller population
  max_generations: 3,   # ← Fewer generations
  # ...
)
```

### Increase Parallelism

Local models can benefit from higher parallelism if you have multiple CPU cores:

```elixir
GEPA.run(agent,
  model: "ollama:llama3.1",
  parallelism: 8,  # ← Higher for local (default: 5)
  # ...
)
```

### Focus on Fewer Objectives

Optimize for objectives that matter with local models:

```elixir
# Cloud: optimize cost, latency, accuracy, robustness
objectives: [:accuracy, :latency, :cost, :robustness]

# Local: cost doesn't matter, focus on quality and speed
objectives: [:accuracy, :latency]
```

---

## Troubleshooting

### Ollama Not Running

**Problem**: `Connection refused` or `ECONNREFUSED`

**Solution**:
```bash
# Start Ollama service
ollama serve

# In another terminal, verify it's running:
curl http://localhost:11434/api/tags
```

### Model Not Found

**Problem**: `Model 'llama3.1' not found`

**Solution**:
```bash
# List available models
ollama list

# Pull the model if needed
ollama pull llama3.1

# Verify it's available
ollama list | grep llama3.1
```

### Out of Memory

**Problem**: System freezes or crashes during optimization

**Solution**:
- Use a smaller model: `phi3` (2.3GB) instead of `llama3.1:70b` (40GB)
- Reduce population size: `population_size: 3`
- Reduce parallelism: `parallelism: 1`
- Check available RAM: `free -h` (Linux) or Activity Monitor (Mac)

### Slow Performance

**Problem**: Optimization takes very long

**Solution**:
```elixir
# Reduce iterations
GEPA.run(agent,
  population_size: 3,      # ← Smaller
  max_generations: 2,      # ← Fewer
  parallelism: 4,          # ← Higher if you have cores
  # ...
)

# Or use a faster model
model: "ollama:phi3"  # Much faster than llama3.1:70b
```

### Wrong Ollama Port

**Problem**: Ollama runs on non-default port

**Solution**: ReqLLM uses `http://localhost:11434` by default. If your Ollama runs on a different port, you'll need to configure it (see ReqLLM documentation).

---

## Comparing Local vs Cloud

### When to Use Local LLMs

✅ **Development and Testing**: Iterate quickly without costs
✅ **Privacy-Sensitive Data**: Keep data on your machine
✅ **Learning GEPA**: Experiment freely without budget concerns
✅ **Offline Work**: No internet required
✅ **High Volume**: Unlimited optimization runs

### When to Use Cloud APIs

✅ **Production Quality**: Need the best results
✅ **Speed Critical**: Cloud inference is faster
✅ **Limited Hardware**: Don't have 8GB+ RAM available
✅ **Latest Models**: Access to newest, most capable models
✅ **No Setup**: Just need an API key

### Hybrid Approach

Many users combine both:

```elixir
# Development: Use local models
{:ok, result, _} = GEPA.run(agent,
  model: "ollama:llama3.1",
  population_size: 5,
  max_generations: 3,
  # ...
)

# Production: Use cloud for final optimization
{:ok, result, _} = GEPA.run(agent,
  model: "openai:gpt-4",
  population_size: 20,
  max_generations: 10,
  # ...
)
```

---

## Next Steps

- **Try Different Models**: Experiment with various local models to find the best balance
- **Tune Configuration**: Adjust population size and generations for your hardware
- **Task-Specific Evaluation**: Use GEPA's task-specific evaluators with local models
- **Monitor Performance**: Track optimization time and quality with different models

For more information:
- [Main GEPA Guide](gepa.md)
- [Ollama Documentation](https://github.com/ollama/ollama)
- [ReqLLM Provider Documentation](https://hexdocs.pm/req_llm)
