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
  @spec resolve_directive_model(map()) :: term() | nil
  def resolve_directive_model(%{model: model}) when is_binary(model) and model != "", do: model

  def resolve_directive_model(%{model_alias: alias_atom}) when is_atom(alias_atom) and not is_nil(alias_atom) do
    Jido.AI.resolve_model(alias_atom)
  end

  def resolve_directive_model(%{model: nil, model_alias: nil} = directive) do
    if directive_backend(directive) == :harness do
      nil
    else
      raise ArgumentError, "Either model or model_alias must be provided"
    end
  end

  def resolve_directive_model(%{"model" => nil, "model_alias" => nil} = directive) do
    if directive_backend(directive) == :harness do
      nil
    else
      raise ArgumentError, "Either model or model_alias must be provided"
    end
  end

  def resolve_directive_model(%{model: nil, model_alias: _alias}) do
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
    backend = directive_backend(directive)
    context = Map.get(directive, :context, Map.get(directive, "context"))
    messages = normalize_directive_messages(context)
    explicit_system_prompt = Map.get(directive, :system_prompt, Map.get(directive, "system_prompt"))

    {prompt, messages, system_prompt} =
      case maybe_prompt_only_request(backend, context, explicit_system_prompt) do
        {:ok, prompt, system_prompt} -> {prompt, [], system_prompt}
        :unsupported -> {nil, messages, explicit_system_prompt}
      end

    Request.new(%{
      request_id: Map.get(directive, :id),
      backend: backend,
      operation: :text,
      prompt: prompt,
      messages: messages,
      system_prompt: system_prompt,
      model: resolve_directive_model(directive),
      timeout_ms: Map.get(directive, :timeout),
      max_tokens: Map.get(directive, :max_tokens),
      temperature: Map.get(directive, :temperature),
      tool_intent: build_tool_intent(directive),
      workspace: build_workspace(directive),
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
      backend: directive_backend(directive),
      operation: :embedding,
      model: Map.get(directive, :model),
      inputs: List.wrap(Map.get(directive, :texts)),
      timeout_ms: Map.get(directive, :timeout),
      workspace: build_workspace(directive),
      backend_metadata: build_embedding_backend_metadata(directive),
      metadata: Map.get(directive, :metadata, %{})
    })
  end

  @doc false
  @spec result_to_turn(Result.t()) :: Turn.t()
  def result_to_turn(%Result{} = result), do: Turn.from_result_map(result)

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
    |> explicit_backend_metadata()
    |> maybe_put_backend_metadata(:req_http_options, Map.get(directive, :req_http_options, []))
  end

  defp build_embedding_backend_metadata(directive) do
    directive
    |> explicit_backend_metadata()
    |> maybe_put_backend_metadata(:dimensions, Map.get(directive, :dimensions))
  end

  defp directive_backend(directive) when is_map(directive) do
    Backends.request_backend(directive)
  end

  defp explicit_backend_metadata(directive) when is_map(directive) do
    directive
    |> Map.get(:backend_metadata, Map.get(directive, "backend_metadata", %{}))
    |> normalize_map_value()
  end

  defp build_workspace(directive) when is_map(directive) do
    workspace =
      directive
      |> Map.get(:workspace, Map.get(directive, "workspace", %{}))
      |> normalize_map_value()

    if map_size(workspace) == 0, do: nil, else: workspace
  end

  defp maybe_prompt_only_request(:harness, context, fallback_system_prompt) do
    extract_single_prompt(context, fallback_system_prompt)
  end

  defp maybe_prompt_only_request(_backend, _context, _fallback_system_prompt), do: :unsupported

  defp extract_single_prompt(prompt, fallback_system_prompt) when is_binary(prompt) and prompt != "" do
    {:ok, prompt, normalize_optional_text(fallback_system_prompt)}
  end

  defp extract_single_prompt(%{messages: messages}, fallback_system_prompt) when is_list(messages),
    do: extract_single_prompt(messages, fallback_system_prompt)

  defp extract_single_prompt(%{"messages" => messages}, fallback_system_prompt) when is_list(messages),
    do: extract_single_prompt(messages, fallback_system_prompt)

  defp extract_single_prompt([message], fallback_system_prompt) do
    case message_role(message) do
      role when role in [:user, "user"] ->
        message
        |> message_content()
        |> content_to_text()
        |> case do
          nil -> :unsupported
          prompt -> {:ok, prompt, normalize_optional_text(fallback_system_prompt)}
        end

      _ ->
        :unsupported
    end
  end

  defp extract_single_prompt([system_message, user_message], fallback_system_prompt) do
    case {message_role(system_message), message_role(user_message)} do
      {system_role, user_role} when system_role in [:system, "system"] and user_role in [:user, "user"] ->
        with system_prompt when not is_nil(system_prompt) <-
               normalize_optional_text(fallback_system_prompt) ||
                 system_message |> message_content() |> content_to_text(),
             prompt when not is_nil(prompt) <- user_message |> message_content() |> content_to_text() do
          {:ok, prompt, system_prompt}
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  defp extract_single_prompt(_context, _fallback_system_prompt), do: :unsupported

  defp message_role(%{role: role}), do: role
  defp message_role(%{"role" => role}), do: role
  defp message_role(_), do: nil

  defp message_content(%{content: content}), do: content
  defp message_content(%{"content" => content}), do: content
  defp message_content(_), do: nil

  defp content_to_text(content) when is_binary(content) and content != "", do: content

  defp content_to_text(parts) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{text: text} when is_binary(text) -> text
      %{"text" => text} when is_binary(text) -> text
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp content_to_text(_), do: nil

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_optional_text(_), do: nil

  defp maybe_put_backend_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_backend_metadata(metadata, _key, []), do: metadata
  defp maybe_put_backend_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp normalize_map_value(value) when is_list(value), do: Map.new(value)
  defp normalize_map_value(value) when is_map(value), do: value
  defp normalize_map_value(_), do: %{}
end
