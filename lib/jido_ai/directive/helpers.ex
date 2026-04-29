defmodule Jido.AI.Directive.Helpers do
  # covers: jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Helper functions for DirectiveExec implementations.

  This module centralizes directive runtime helpers for:
  - Task supervisor resolution
  - Model resolution from directive fields
  - Message normalization/building
  - Backend request assembly
  - Error classification
  """

  alias Jido.AI.Backend.{Request, Result}
  alias Jido.AI.Backends
  alias Jido.AI.Turn

  @doc """
  Gets the task supervisor from agent state.

  First checks the TaskSupervisorSkill's internal state (`__task_supervisor_skill__`),
  then falls back to the top-level `:task_supervisor` field for standalone usage.

  ## Examples

      iex> state = %{__task_supervisor_skill__: %{supervisor: supervisor_pid}}
      iex> Jido.AI.Directive.Helpers.get_task_supervisor(state)
      supervisor_pid

      iex> state = %{task_supervisor: supervisor_pid}
      iex> Jido.AI.Directive.Helpers.get_task_supervisor(state)
      supervisor_pid

  """
  def get_task_supervisor(%Jido.AgentServer.State{agent: agent}) do
    # Handle AgentServer.State struct - extract the agent's state
    get_task_supervisor(agent.state)
  end

  def get_task_supervisor(state) when is_map(state) do
    # First check TaskSupervisorSkill's internal state
    case Map.get(state, :__task_supervisor_skill__) do
      %{supervisor: supervisor} when is_pid(supervisor) ->
        supervisor

      _ ->
        # Fall back to top-level state field (for standalone usage)
        case Map.get(state, :task_supervisor) do
          nil ->
            raise """
            Task supervisor not found in agent state.

            In Jido 2.0, each agent instance requires its own task supervisor.
            Ensure your agent is started with Jido.AI which will automatically
            create and store a per-instance supervisor in the agent state.

            Example:
                use Jido.AI.Agent,
                  name: "my_agent",
                  tools: [MyApp.Tool1, MyApp.Tool2]
            """

          supervisor when is_pid(supervisor) ->
            supervisor
        end
    end
  end

  @doc """
  Resolves a model from directive fields.

  Supports both direct model specification and model alias resolution.
  """
  @spec resolve_directive_model(map()) :: String.t()
  def resolve_directive_model(%{model: model}) when is_binary(model) and model != "", do: model

  def resolve_directive_model(%{model_alias: alias_atom}) when is_atom(alias_atom) and not is_nil(alias_atom) do
    Jido.AI.resolve_model(alias_atom)
  end

  def resolve_directive_model(%{model: nil, model_alias: nil}) do
    raise ArgumentError, "Either model or model_alias must be provided"
  end

  def resolve_directive_model(_) do
    raise ArgumentError, "Either model or model_alias must be provided"
  end

  @doc """
  Builds messages for LLM calls from context and optional system prompt.
  """
  @spec build_directive_messages(term(), String.t() | nil) :: list()
  def build_directive_messages(context, nil), do: normalize_directive_messages(context)

  def build_directive_messages(context, system_prompt) when is_binary(system_prompt) do
    messages = normalize_directive_messages(context)
    system_message = %{role: :system, content: system_prompt}
    [system_message | messages]
  end

  @doc false
  @spec normalize_directive_messages(term()) :: list()
  def normalize_directive_messages(%{messages: msgs}) when is_list(msgs), do: msgs
  def normalize_directive_messages(%{"messages" => msgs}) when is_list(msgs), do: msgs
  def normalize_directive_messages(msgs) when is_list(msgs), do: msgs
  def normalize_directive_messages(_context), do: []

  @doc """
  Builds a backend-neutral text request for directive-driven LLM execution.
  """
  @spec build_llm_request(map()) :: Request.t()
  def build_llm_request(directive) when is_map(directive) do
    Request.new(%{
      request_id: Map.get(directive, :id),
      backend: Backends.default_backend(),
      operation: :text,
      messages: normalize_directive_messages(Map.get(directive, :context)),
      system_prompt: Map.get(directive, :system_prompt),
      model: resolve_directive_model(directive),
      timeout_ms: Map.get(directive, :timeout),
      max_tokens: Map.get(directive, :max_tokens),
      temperature: Map.get(directive, :temperature),
      tool_intent: build_tool_intent(directive),
      backend_metadata: build_llm_backend_metadata(directive),
      metadata: Map.get(directive, :metadata, %{})
    })
  end

  @doc """
  Builds a backend-neutral embedding request for directive-driven execution.
  """
  @spec build_embedding_request(map()) :: Request.t()
  def build_embedding_request(directive) when is_map(directive) do
    Request.new(%{
      request_id: Map.get(directive, :id),
      backend: Backends.default_backend(),
      operation: :embedding,
      model: Map.get(directive, :model),
      inputs: List.wrap(Map.get(directive, :texts)),
      timeout_ms: Map.get(directive, :timeout),
      backend_metadata: build_embedding_backend_metadata(directive),
      metadata: Map.get(directive, :metadata, %{})
    })
  end

  @doc false
  @spec result_to_turn(Result.t()) :: Turn.t()
  def result_to_turn(%Result{} = result) do
    Turn.from_result_map(%{
      type: classify_result_type(result),
      text: result.text,
      thinking_content: result.thinking_content,
      reasoning_details: result.reasoning_details,
      tool_calls: result.tool_calls,
      usage: result.usage,
      model: result.model,
      finish_reason: result.finish_reason,
      message_metadata: result.message_metadata
    })
  end

  @doc """
  Adds timeout option to a keyword list if timeout is specified.
  """
  @spec add_timeout_opt(keyword(), integer() | nil) :: keyword()
  def add_timeout_opt(opts, nil), do: opts

  def add_timeout_opt(opts, timeout) when is_integer(timeout) do
    Keyword.put(opts, :receive_timeout, timeout)
  end

  @doc """
  Adds req_http_options option to a keyword list if options are specified.
  """
  @spec add_req_http_options(keyword(), list() | nil) :: keyword()
  def add_req_http_options(opts, nil), do: opts
  def add_req_http_options(opts, []), do: opts

  def add_req_http_options(opts, req_http_options) when is_list(req_http_options) do
    Keyword.put(opts, :req_http_options, req_http_options)
  end

  @doc """
  Adds tools option to a keyword list if tools are specified.
  """
  @spec add_tools_opt(keyword(), list()) :: keyword()
  def add_tools_opt(opts, []), do: opts
  def add_tools_opt(opts, tools), do: Keyword.put(opts, :tools, tools)

  @doc """
  Classifies an error into a runtime category.

  Returns one of: `:rate_limit`, `:auth`, `:timeout`, `:provider_error`,
  `:network`, `:validation`, `:unknown`.
  """
  @spec classify_error(term()) :: atom()
  def classify_error(%{status: status}) when status == 429, do: :rate_limit
  def classify_error(%{status: status}) when status in [401, 403], do: :auth
  def classify_error(%{status: status}) when status >= 500, do: :provider_error
  def classify_error(%{status: status}) when status >= 400, do: :validation

  def classify_error(%{reason: :timeout}), do: :timeout
  def classify_error(%{reason: :connect_timeout}), do: :timeout
  def classify_error(%{reason: :checkout_timeout}), do: :timeout

  def classify_error(%{reason: reason}) when reason in [:econnrefused, :nxdomain, :closed], do: :network

  def classify_error({:error, :timeout}), do: :timeout
  def classify_error(:timeout), do: :timeout

  def classify_error(%Mint.TransportError{}), do: :network
  def classify_error(%Mint.HTTPError{}), do: :network

  def classify_error(_), do: :unknown

  defp build_tool_intent(directive) do
    tools = Map.get(directive, :tools, [])

    if is_list(tools) and tools != [] do
      %{
        tools: tools,
        tool_choice: Map.get(directive, :tool_choice)
      }
    else
      nil
    end
  end

  defp build_llm_backend_metadata(directive) do
    directive
    |> Map.get(:req_http_options, [])
    |> case do
      [] -> %{}
      req_http_options when is_list(req_http_options) -> %{req_http_options: req_http_options}
      _ -> %{}
    end
  end

  defp build_embedding_backend_metadata(directive) do
    case Map.get(directive, :dimensions) do
      dimensions when is_integer(dimensions) -> %{dimensions: dimensions}
      _ -> %{}
    end
  end

  defp classify_result_type(%Result{tool_calls: [_ | _]}), do: :tool_calls
  defp classify_result_type(%Result{finish_reason: :tool_calls}), do: :tool_calls
  defp classify_result_type(_result), do: :final_answer
end
