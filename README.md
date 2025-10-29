# Jido AI

**Intelligent Agent Framework for Elixir**

Jido AI is a comprehensive framework for building sophisticated AI agents and workflows in Elixir. It extends the [Jido](https://github.com/agentjido/jido) framework with powerful LLM capabilities, advanced reasoning techniques, and stateful conversation management.

## What is Jido AI?

Jido AI provides the tools and patterns you need to build production-ready AI agents that can:

- **Reason Intelligently**: Implement advanced reasoning frameworks (Chain-of-Thought, ReAct, Tree-of-Thoughts, Self-Consistency, Program-of-Thought)
- **Maintain Context**: Manage stateful multi-turn conversations with tool integration
- **Use Tools Effectively**: Execute function calls and integrate with external systems
- **Work with Multiple Providers**: Support for Anthropic, OpenAI, Google Gemini, OpenRouter, Cloudflare, and more
- **Generate Structured Output**: Parse LLM responses into validated Ecto schemas
- **Handle Complex Workflows**: Orchestrate multi-step AI operations with Jido.Exec

Whether you're building a chatbot, research assistant, code generator, or autonomous agent, Jido AI provides the building blocks you need.

---

## Installation

Add Jido AI to your dependencies:

```elixir
def deps do
  [
    {:jido, "~> 1.2.0"},
    {:jido_ai, "~> 0.5.2"}
  ]
end
```

## Configuration

Configure your LLM provider. Here's an example for Anthropic:

```elixir
# config/config.exs
config :instructor,
  adapter: Instructor.Adapters.Anthropic,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ]
```

For other providers, see the [Providers Guide](guides/providers/providers.md).

---

## Quick Start

Here's a simple example that extracts structured information about US politicians:

```elixir
defmodule MyApp.Politician do
  defmodule Schema do
    use Ecto.Schema
    use Instructor
    @primary_key false
    embedded_schema do
      field(:first_name, :string)
      field(:last_name, :string)

      embeds_many :offices_held, Office, primary_key: false do
        field(:office, Ecto.Enum,
          values: [:president, :vice_president, :governor, :congress, :senate]
        )
        field(:from_date, :date)
        field(:to_date, :date)
      end
    end
  end

  use Jido.Action,
    name: "politician",
    description: "Extract information about US politicians",
    schema: [
      query: [type: :string, required: true]
    ]

  def run(params, _context) do
    JidoAi.Actions.Anthropic.ChatCompletion.run(
      %{
        model: "claude-3-5-haiku-latest",
        messages: [%{role: "user", content: params.query}],
        response_model: Schema,
        temperature: 0.5,
        max_tokens: 1000
      },
      %{}
    )
  end
end

# Use it
{:ok, result} = Jido.Exec.run(
  MyApp.Politician,
  %{query: "Tell me about Barack Obama's political career"}
)

result.result
# => %MyApp.Politician.Schema{
#      first_name: "Barack",
#      last_name: "Obama",
#      offices_held: [...]
#    }
```

For more examples, see [examples/](examples/).

---

## User Guides

### Core Guides

Foundation guides for using Jido AI:

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/getting-started.md) | Quick start guide and basic concepts |
| [Actions](guides/actions.md) | Building and composing AI actions |
| [Prompt Engineering](guides/prompt.md) | Crafting effective prompts and messages |
| [Keyring](guides/keyring.md) | Managing API keys for LLM providers |
| [Agent Skills](guides/agent-skill.md) | Creating reusable agent capabilities |
| [Troubleshooting](guides/troubleshooting.md) | Common issues and solutions |

### Provider Guides

Connect to various LLM providers:

| Guide | Description |
|-------|-------------|
| [Providers Overview](guides/providers/providers.md) | Supported LLM providers and configuration |
| [Provider Matrix](guides/providers/provider-matrix.md) | Feature comparison across providers |
| [Enterprise Providers](guides/providers/enterprise.md) | Azure, AWS Bedrock, enterprise setups |
| [High Performance](guides/providers/high-performance.md) | Optimization for production workloads |
| [Local Models](guides/providers/local-models.md) | Running models locally (Ollama, etc.) |
| [Regional Providers](guides/providers/regional.md) | Region-specific providers and compliance |
| [Specialized Providers](guides/providers/specialized.md) | Domain-specific models and providers |

### Advanced Topics

Deep dives into advanced features:

| Guide | Description |
|-------|-------------|
| [Advanced Parameters](guides/advanced/advanced-parameters.md) | Fine-tuning model behavior |
| [Code Execution](guides/advanced/code-execution.md) | Executing generated code safely |
| [Context Windows](guides/advanced/context-windows.md) | Managing large context efficiently |
| [Fine-Tuning](guides/advanced/fine-tuning.md) | Custom model training |
| [Plugins](guides/advanced/plugins.md) | Extending Jido AI with plugins |
| [RAG Integration](guides/advanced/rag-integration.md) | Retrieval-Augmented Generation patterns |

### GEPA (Prompt Optimization)

Gradient-Free Evolutionary Prompt Optimization:

| Guide | Description |
|-------|-------------|
| [GEPA Overview](guides/gepa/gepa.md) | Complete guide to evolutionary prompt optimization |
| [GEPA for the Layman](guides/gepa/gepa_for_the_layman.md) | Non-technical introduction to GEPA |

---

## Reasoning Frameworks

Advanced reasoning techniques for complex problem-solving:

### Overview

Jido AI implements state-of-the-art reasoning frameworks that dramatically improve LLM performance on complex tasks. Each framework is suited to different types of problems:

| Framework | Best For | Accuracy Gain | Cost | Latency |
|-----------|----------|---------------|------|---------|
| [Chain-of-Thought](guides/chain_of_thought.md) | Multi-step reasoning | +8-15% | 3-4× | 2-3s |
| [ReAct](guides/react.md) | Tool use, research | +27% | 10-30× | 20-60s |
| [Tree-of-Thoughts](guides/tree_of_thoughts.md) | Planning, games | +70% | 50-150× | 30-120s |
| [Self-Consistency](guides/self_consistency.md) | Critical accuracy | +17.9% | 5-10× | 15-25s |
| [Program-of-Thought](guides/program_of_thought.md) | Math, calculations | +8.5% | 2-3× | 3-8s |

### Chain-of-Thought (CoT)

**Step-by-step reasoning for complex problems**

Chain-of-Thought prompts LLMs to break down problems into intermediate steps, making reasoning explicit and verifiable. Essential for mathematical reasoning, logical deduction, and multi-step planning.

```elixir
# Use CoT runner with any Jido Agent
defmodule MyAgent do
  use Jido.Agent,
    name: "reasoning_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [MyAction]
end
```

📖 [Complete Guide](guides/chain_of_thought.md) | 💡 [Examples](examples/chain-of-thought/)

**Performance**: +8-15% accuracy on complex reasoning tasks with 3-4× token overhead.

### ReAct (Reasoning + Acting)

**Interleaving reasoning with tool execution**

ReAct combines reasoning with action execution in an iterative loop. The model thinks about what to do, executes tools, observes results, and adjusts its approach dynamically.

```elixir
# ReAct automatically coordinates tools
defmodule ResearchAgent do
  use Jido.Agent,
    name: "research_agent",
    runner: Jido.AI.Runner.ReAct,
    actions: [SearchAction, WeatherAction, CalculatorAction]
end
```

📖 [Complete Guide](guides/react.md) | 💡 [Examples](examples/react/)

**Performance**: +27.4% on multi-hop QA tasks, 10-30× cost depending on steps.

### Tree-of-Thoughts (ToT)

**Exploring multiple reasoning paths with backtracking**

Tree-of-Thoughts explores multiple reasoning trajectories simultaneously, evaluates their promise, and backtracks from dead ends. Ideal for strategic planning, game playing, and exhaustive search.

```elixir
# ToT explores solution space systematically
{:ok, result} = Jido.AI.Runner.TreeOfThoughts.run(
  agent,
  search_strategy: :best_first,
  branching_factor: 3,
  max_depth: 5
)
```

📖 [Complete Guide](guides/tree_of_thoughts.md) | 💡 [Examples](examples/tree-of-thoughts/)

**Performance**: +70% on Game of 24, but 50-150× cost. Use for high-value problems only.

### Self-Consistency

**Multiple reasoning paths with voting**

Self-Consistency generates diverse reasoning approaches and uses majority voting to select the most reliable answer. Reduces errors through the "wisdom of the crowd."

```elixir
# Generate multiple paths and vote
{:ok, result} = Jido.AI.Runner.SelfConsistency.run(
  agent,
  sample_count: 7,
  temperature: 0.8,
  voting_strategy: :hybrid
)
```

📖 [Complete Guide](guides/self_consistency.md) | 💡 [Examples](examples/self-consistency/)

**Performance**: +17.9% accuracy on GSM8K, 5-10× cost with k=5-10 samples.

### Program-of-Thought (PoT)

**Separating reasoning from computation**

Program-of-Thought generates executable code for precise calculations instead of asking LLMs to perform arithmetic. Near-zero error rate for mathematical operations.

```elixir
# LLM generates code, code executes calculations
{:ok, result} = Jido.AI.Runner.ProgramOfThought.solve(
  "Calculate compound interest on $10,000 at 5% for 3 years",
  timeout: 10_000,
  validate_safety: true
)
```

📖 [Complete Guide](guides/program_of_thought.md) | 💡 [Examples](examples/program-of-thought/)

**Performance**: +8.5% accuracy on GSM8K, 2-3× cost, near-zero arithmetic errors.

### Choosing a Framework

```
Simple reasoning problem → Chain-of-Thought
Need to use tools → ReAct
Strategic planning required → Tree-of-Thoughts
Critical accuracy needed → Self-Consistency
Mathematical calculations → Program-of-Thought
```

All frameworks include:
- ✅ Complete working examples
- ✅ Production-ready implementations
- ✅ Performance benchmarks
- ✅ Cost analysis
- ✅ Best practices

---

## Conversation Manager

**Stateful multi-turn conversations with tool integration**

The ConversationManager system provides infrastructure for building stateful LLM applications that maintain context across multiple turns and can use tools (function calling).

### Key Features

- **Stateful Context**: Maintains message history across conversation turns
- **Tool Integration**: Seamlessly coordinates tool execution with LLM responses
- **Thread-Safe**: Supports multiple concurrent conversations with isolated state
- **Automatic Cleanup**: Expires conversations after 24 hours
- **Error Handling**: Graceful degradation and retry logic
- **Analytics**: Track conversation metrics and tool usage

### Components

The system consists of three coordinated components:

1. **ConversationManager**: State storage and message history
2. **ToolIntegrationManager**: High-level API for tool-enabled interactions
3. **ToolResponseHandler**: Response processing and tool execution

### Quick Example

```elixir
alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

# Start a conversation with tools
{:ok, conv_id} = ToolIntegrationManager.start_conversation(
  [WeatherAction, CalculatorAction],
  %{model: "gpt-4", temperature: 0.7}
)

# Chat across multiple turns (context preserved)
{:ok, response1} = ToolIntegrationManager.continue_conversation(
  conv_id,
  "What's the weather in Paris?"
)

{:ok, response2} = ToolIntegrationManager.continue_conversation(
  conv_id,
  "And in London?"
)

{:ok, response3} = ToolIntegrationManager.continue_conversation(
  conv_id,
  "Which city is warmer?"  # Uses context from previous turns
)

# Get full history
{:ok, history} = ToolIntegrationManager.get_conversation_history(conv_id)

# Cleanup
:ok = ToolIntegrationManager.end_conversation(conv_id)
```

### Advanced Features

- **Multi-tool coordination**: Execute multiple tools in parallel
- **Error recovery**: Automatic retry with exponential backoff
- **Streaming responses**: Support for real-time streaming
- **Conversation analytics**: Track usage, timing, and patterns
- **State management**: Fork, persist, and restore conversations

📖 [Complete Guide](guides/conversation_manager.md) | 💡 [Examples](examples/conversation-manager/)

**Performance**: In-memory ETS storage, 4 concurrent tool executions, 30s default timeout.

---

## Supported Providers

Jido AI supports multiple LLM providers with consistent APIs:

| Provider | Models | Features |
|----------|--------|----------|
| **Anthropic** | Claude 3.5 Sonnet, Haiku | Structured output, tool use, vision |
| **OpenAI** | GPT-4, GPT-4 Turbo, o1 | Function calling, vision, DALL-E |
| **Google** | Gemini 2.0, Gemini Pro | Multimodal, long context |
| **OpenRouter** | 100+ models | Model routing, fallbacks |
| **Cloudflare** | Workers AI | Edge deployment |
| **Local** | Ollama, LM Studio | Privacy, no API costs |

### Using Google Gemini

```elixir
# Set your API key
Jido.AI.Keyring.set_session_value(:google_api_key, "your_gemini_api_key")

# Create a model
{:ok, model} = Jido.AI.Model.from({:google, [model: "gemini-2.0-flash"]})

# Use with actions
result = Jido.AI.Actions.OpenaiEx.run(
  %{
    model: model,
    messages: [%{role: :user, content: "Tell me about Elixir"}],
    temperature: 0.7
  },
  %{}
)
```

Environment variables work too:
```bash
GOOGLE_API_KEY=your_gemini_api_key
```

See the [Providers Guide](guides/providers/providers.md) for complete configuration details.

---

## Message Handling

Jido AI provides robust message handling with support for rich content:

```elixir
alias Jido.AI.Prompt.MessageItem

# Simple text message
user_msg = MessageItem.new(%{role: :user, content: "Hello"})

# System message
system_msg = MessageItem.new(%{
  role: :system,
  content: "You are a helpful assistant"
})

# Multipart message with image
rich_msg = MessageItem.new_multipart(:user, [
  MessageItem.text_part("Check out this image:"),
  MessageItem.image_part("https://example.com/image.jpg")
])

# Template-based message
template_msg = MessageItem.new(%{
  role: :system,
  content: "You are a <%= @assistant_type %>",
  engine: :eex
})
```

---

## LLM Keyring

The Keyring system manages API keys for various LLM providers securely and conveniently.

### Key Features

- **Multiple Sources**: Environment variables, application config, defaults
- **Session Keys**: Per-process keys for isolated contexts
- **Priority System**: Environment > Application > Defaults
- **Validation**: Test keys before use

### Usage

```elixir
# Get a key (checks session first, then environment)
api_key = Jido.AI.Keyring.get_key(:anthropic)

# Set a session-specific key (current process only)
Jido.AI.Keyring.set_session_key(:anthropic, "my_session_key")

# Test if a key is valid
case Jido.AI.Keyring.test_key(:anthropic, api_key) do
  {:ok, _response} -> IO.puts("Key is valid!")
  {:error, reason} -> IO.puts("Key test failed: #{inspect(reason)}")
end

# Clear session keys
Jido.AI.Keyring.clear_all_session_keys()
```

### Configuration

```elixir
# config/config.exs
config :jido_ai, :instructor,
  anthropic: [api_key: "your_anthropic_key"]

config :jido_ai, :openai,
  api_key: "your_openai_key"
```

Or use environment variables:
```bash
ANTHROPIC_API_KEY=your_anthropic_key
OPENAI_API_KEY=your_openai_key
```

See the [Keyring Guide](guides/keyring.md) for detailed documentation.

---

## Migration Guides

If you're migrating from other frameworks or upgrading Jido AI:

- [Migration Overview](guides/migration/) - Guide for various migration scenarios

---

## Examples

Explore complete working examples in the [examples/](examples/) directory:

- **Politician Extractor** ([politician.ex](examples/politician.ex)) - Structured data extraction
- **Chain-of-Thought** ([examples/chain-of-thought/](examples/chain-of-thought/)) - Step-by-step reasoning
- **ReAct** ([examples/react/](examples/react/)) - Tool-enabled research assistant
- **Tree-of-Thoughts** ([examples/tree-of-thoughts/](examples/tree-of-thoughts/)) - Strategic planning
- **Self-Consistency** ([examples/self-consistency/](examples/self-consistency/)) - Multi-path voting
- **Program-of-Thought** ([examples/program-of-thought/](examples/program-of-thought/)) - Code-based computation
- **Conversation Manager** ([examples/conversation-manager/](examples/conversation-manager/)) - Stateful conversations
- **GEPA** ([examples/gepa/](examples/gepa/)) - Prompt optimization

---

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/jido_ai).

To generate documentation locally:

```bash
mix docs
```

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

Jido AI is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## Resources

- [GitHub Repository](https://github.com/agentjido/jido_ai)
- [HexDocs](https://hexdocs.pm/jido_ai)
- [Jido Framework](https://github.com/agentjido/jido)
- [Elixir Forum](https://elixirforum.com/)
- [Discord Community](https://discord.gg/jido-ai) _(if available)_

---

## Acknowledgments

Jido AI builds on the excellent work of:

- [Instructor](https://github.com/thmsmlr/instructor_ex) - Structured LLM outputs for Elixir
- [Jido](https://github.com/agentjido/jido) - Agent framework foundation
- The Elixir community for their invaluable feedback and contributions

---

**Built with ❤️ using Elixir**
