defmodule Jido.Skills.ChainOfThought do
  @moduledoc """
  Chain-of-Thought reasoning skill for Jido agents.

  This skill provides advanced reasoning capabilities through Chain-of-Thought (CoT) patterns,
  enabling agents to perform step-by-step reasoning before executing actions. The skill can be
  mounted on any agent to add transparent reasoning capabilities without modifying existing actions.

  ## Overview

  The ChainOfThought skill encapsulates various reasoning patterns:
  - Zero-shot reasoning ("Let's think step by step")
  - Few-shot reasoning with examples
  - Structured reasoning for specific tasks
  - Self-consistency with multiple samples
  - Self-correction and iterative refinement

  ## Usage

  Mount the skill on an agent to enable CoT capabilities:

      defmodule MyAgent do
        use Jido.Agent,
          name: "reasoning_agent",
          actions: [MyAction]
      end

      # Create agent
      {:ok, agent} = MyAgent.new()

      # Mount CoT skill
      {:ok, agent} = Jido.Skills.ChainOfThought.mount(agent, [
        mode: :zero_shot,
        max_iterations: 3,
        enable_backtracking: true
      ])

      # Agent now has CoT capabilities configured

  ## Configuration

  The skill accepts the following configuration options:

  - `:mode` - Reasoning mode (default: `:zero_shot`)
    - `:zero_shot` - Simple step-by-step reasoning
    - `:few_shot` - Reasoning with examples
    - `:structured` - Task-specific structured reasoning
    - `:self_consistency` - Multiple reasoning samples with voting

  - `:max_iterations` - Maximum reasoning refinement iterations (default: `3`)

  - `:samples` - Number of reasoning samples for self-consistency (default: `3`)

  - `:enable_backtracking` - Enable backtracking on errors (default: `true`)

  - `:temperature` - Temperature for reasoning generation (default: `0.7`)

  - `:model` - LLM model to use (default: `"gpt-4o"`)

  - `:enable_validation` - Enable outcome validation (default: `true`)

  ## Examples

      # Basic zero-shot reasoning
      {:ok, agent} = Jido.Skills.ChainOfThought.mount(agent, mode: :zero_shot)

      # Self-consistency with 5 samples
      {:ok, agent} = Jido.Skills.ChainOfThought.mount(agent, [
        mode: :self_consistency,
        samples: 5
      ])

      # Structured reasoning for code generation
      {:ok, agent} = Jido.Skills.ChainOfThought.mount(agent, [
        mode: :structured,
        max_iterations: 5,
        enable_validation: true
      ])

  ## State Management

  The skill stores its configuration in the agent's state under the `:cot` key.
  This configuration is used by CoT actions and the custom runner when processing
  instructions.

  ## Integration

  The CoT skill works with:
  - `Jido.Runner.ChainOfThought` - Custom runner for transparent CoT
  - Lifecycle hooks (`on_before_plan`, `on_before_run`, `on_after_run`)
  - CoT-specific actions (when implemented via Task 1.3.2)

  ## See Also

  - `Jido.Runner.ChainOfThought` - Custom CoT runner
  - `Jido.Runner.ChainOfThought.PlanningHook` - Planning lifecycle hook
  - `Jido.Runner.ChainOfThought.ExecutionHook` - Execution lifecycle hook
  - `Jido.Runner.ChainOfThought.ValidationHook` - Validation lifecycle hook
  """

  use Jido.Skill,
    name: "chain_of_thought",
    description: "Provides Chain-of-Thought reasoning capabilities for agents",
    category: "reasoning",
    tags: ["reasoning", "cot", "llm", "ai"],
    vsn: "1.0.0",
    opts_key: :cot,
    opts_schema: [
      mode: [
        type: {:in, [:zero_shot, :few_shot, :structured, :self_consistency]},
        default: :zero_shot,
        doc: "Reasoning mode to use"
      ],
      max_iterations: [
        type: :pos_integer,
        default: 3,
        doc: "Maximum reasoning refinement iterations"
      ],
      samples: [
        type: :pos_integer,
        default: 3,
        doc: "Number of reasoning samples for self-consistency mode"
      ],
      enable_backtracking: [
        type: :boolean,
        default: true,
        doc: "Enable backtracking on errors"
      ],
      temperature: [
        type: :float,
        default: 0.7,
        doc: "Temperature for reasoning generation (0.0-1.0)"
      ],
      model: [
        type: :string,
        default: "gpt-4o",
        doc: "LLM model to use for reasoning"
      ],
      enable_validation: [
        type: :boolean,
        default: true,
        doc: "Enable outcome validation against reasoning"
      ]
    ],
    signal_patterns: [
      "agent.reasoning.*",
      "agent.cot.*"
    ]

  alias Jido.Agent

  @doc """
  Mounts the ChainOfThought skill on an agent.

  This function configures the agent with CoT capabilities by adding the skill's
  configuration to the agent's state. The configuration is validated and stored
  under the `:cot` key for use by CoT actions and the custom runner.

  ## Parameters

  - `agent` - The agent struct to mount the skill on
  - `opts` - Configuration options (keyword list)

  ## Options

  See module documentation for available options.

  ## Returns

  - `{:ok, agent}` - Successfully mounted skill
  - `{:error, reason}` - Failed to mount skill

  ## Examples

      # Mount with default configuration
      {:ok, agent} = Jido.Skills.ChainOfThought.mount(agent, [])

      # Mount with custom configuration
      {:ok, agent} = Jido.Skills.ChainOfThought.mount(agent, [
        mode: :structured,
        max_iterations: 5,
        temperature: 0.8
      ])

  ## State Structure

  The skill adds the following to agent state:

      %{
        cot: %{
          mode: :zero_shot,
          max_iterations: 3,
          samples: 3,
          enable_backtracking: true,
          temperature: 0.7,
          model: "gpt-4o",
          enable_validation: true
        }
      }
  """
  @impl Jido.Skill
  def mount(agent, opts) when is_list(opts) do
    # Get schema and validate configuration
    with {:ok, schema} <- Jido.Skill.get_opts_schema(__MODULE__),
         {:ok, validated_config} <- NimbleOptions.validate(opts, schema) do
      # Convert validated keyword list to map for storage
      config_map = Enum.into(validated_config, %{})
      # Add validated configuration to agent state
      updated_agent = add_cot_config(agent, config_map)
      {:ok, updated_agent}
    end
  end

  @doc """
  Adds CoT configuration to agent state.

  This is a helper function that safely adds or updates the CoT configuration
  in the agent's state under the `:cot` key. It preserves any existing state.

  ## Parameters

  - `agent` - The agent struct
  - `config` - Validated CoT configuration map

  ## Returns

  The updated agent with CoT configuration in state

  ## Examples

      config = %{
        mode: :zero_shot,
        max_iterations: 3,
        temperature: 0.7
      }

      agent = Jido.Skills.ChainOfThought.add_cot_config(agent, config)
      # => %Agent{state: %{cot: config, ...}}
  """
  @spec add_cot_config(Agent.t(), map()) :: Agent.t()
  def add_cot_config(agent, config) do
    current_state = agent.state || %{}
    updated_state = Map.put(current_state, :cot, config)
    %{agent | state: updated_state}
  end

  @doc """
  Retrieves CoT configuration from agent state.

  Returns the CoT configuration if the skill has been mounted, otherwise
  returns an error.

  ## Parameters

  - `agent` - The agent struct

  ## Returns

  - `{:ok, config}` - CoT configuration map
  - `{:error, :not_mounted}` - Skill not mounted on agent

  ## Examples

      {:ok, config} = Jido.Skills.ChainOfThought.get_cot_config(agent)
      # => {:ok, %{mode: :zero_shot, ...}}

      # Agent without skill mounted
      Jido.Skills.ChainOfThought.get_cot_config(agent)
      # => {:error, :not_mounted}
  """
  @spec get_cot_config(Agent.t()) :: {:ok, map()} | {:error, :not_mounted}
  def get_cot_config(agent) do
    case get_in(agent, [:state, :cot]) do
      nil -> {:error, :not_mounted}
      config when is_map(config) -> {:ok, config}
    end
  end

  @doc """
  Updates CoT configuration on a mounted skill.

  Merges new configuration with existing configuration, validating the result.

  ## Parameters

  - `agent` - The agent struct
  - `updates` - Configuration updates (keyword list or map)

  ## Returns

  - `{:ok, agent}` - Successfully updated configuration
  - `{:error, :not_mounted}` - Skill not mounted
  - `{:error, reason}` - Invalid configuration

  ## Examples

      # Update temperature
      {:ok, agent} = Jido.Skills.ChainOfThought.update_config(agent, temperature: 0.9)

      # Update multiple settings
      {:ok, agent} = Jido.Skills.ChainOfThought.update_config(agent, [
        mode: :structured,
        max_iterations: 5
      ])
  """
  @spec update_config(Agent.t(), keyword() | map()) ::
          {:ok, Agent.t()} | {:error, :not_mounted | term()}
  def update_config(agent, updates) when is_list(updates) or is_map(updates) do
    updates_map = if is_list(updates), do: Enum.into(updates, %{}), else: updates

    with {:ok, current_config} <- get_cot_config(agent),
         merged_config = Map.merge(current_config, updates_map),
         # Convert merged map to keyword list for validation
         merged_list = Enum.into(merged_config, []),
         {:ok, schema} <- Jido.Skill.get_opts_schema(__MODULE__),
         {:ok, validated_config} <- NimbleOptions.validate(merged_list, schema) do
      # Convert validated keyword list back to map
      config_map = Enum.into(validated_config, %{})
      updated_agent = add_cot_config(agent, config_map)
      {:ok, updated_agent}
    end
  end

  @doc """
  Checks if the CoT skill is mounted on an agent.

  ## Parameters

  - `agent` - The agent struct

  ## Returns

  - `true` if skill is mounted
  - `false` if skill is not mounted

  ## Examples

      Jido.Skills.ChainOfThought.mounted?(agent)
      # => true
  """
  @spec mounted?(Agent.t()) :: boolean()
  def mounted?(agent) do
    case get_cot_config(agent) do
      {:ok, _config} -> true
      {:error, :not_mounted} -> false
    end
  end
end
