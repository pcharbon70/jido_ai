defmodule Jido.AI.Backends.Harness do
  # covers: jido_ai.runtime_contracts.backend_normalization_boundary jido_ai.core_runtime.additive_backend_selection
  @moduledoc """
  Jido.Harness-backed implementation of the internal backend contract.

  This adapter translates canonical Jido.AI backend requests into
  `Jido.Harness.RunRequest` structs and normalizes streamed CLI-agent events
  back into canonical backend results and progress events.
  """

  @behaviour Jido.AI.Backend

  alias Jido.AI.Backend
  alias Jido.AI.Backend.{Capabilities, Event, Request, Result}
  alias Jido.AI.Backends
  alias Jido.AI.Error
  alias Jido.Harness
  alias Jido.Harness.Capabilities, as: HarnessCapabilities
  alias Jido.Harness.Event, as: HarnessEvent
  alias Jido.Harness.RunRequest, as: HarnessRunRequest

  @delta_event_types [:delta, :text_delta, :message_delta, :output_text_delta, :token]
  @thinking_event_types [:thinking, :reasoning, :analysis, :thought_delta]
  @tool_call_event_types [:tool_call]
  @tool_result_event_types [:tool_result]
  @completed_event_types [:completed, :completion, :final, :response, :result]
  @failed_event_types [:error, :failed]
  @cancelled_event_types [:cancelled, :canceled]
  @metadata_event_types [:metadata, :session, :started, :run_started, :session_started, :file_change]

  @type adapter_context :: %{
          request: Request.t(),
          provider: atom(),
          run_request: HarnessRunRequest.t(),
          run_opts: keyword(),
          provider_capabilities: HarnessCapabilities.t() | nil
        }

  @type adapter_state :: %{
          provider: atom(),
          model: String.t() | nil,
          session_id: String.t() | nil,
          timestamp: String.t() | nil,
          text_parts: [String.t()],
          thinking_parts: [String.t()],
          tool_calls: [map()],
          usage: map() | nil,
          finish_reason: term(),
          completed_payload: map(),
          metadata: map(),
          raw_events: [HarnessEvent.t()]
        }

  @impl true
  def id, do: :harness

  @impl true
  def capabilities do
    Capabilities.new(
      text_generation: true,
      streaming: true,
      structured_output: false,
      embeddings: false,
      local_tools: false,
      cancellation: true,
      message_history: false,
      workspace_execution: true
    )
  end

  @impl true
  def generate(%Request{} = request) do
    with {:ok, context} <- prepare_request(request),
         :ok <- validate_prompt_request(context.request),
         {:ok, state} <- consume_harness_stream(context, nil) do
      {:ok, build_result(context, state)}
    end
  end

  @impl true
  def stream(%Request{} = request) do
    request = %{request | stream?: true}

    with {:ok, context} <- prepare_request(request),
         :ok <- validate_prompt_request(context.request),
         {:ok, stream} <- run_harness_request(context) do
      {:ok, build_event_stream(context, stream)}
    end
  end

  @impl true
  def cancel(session_id, opts) when is_binary(session_id) and session_id != "" and is_list(opts) do
    with {:ok, provider} <- normalize_provider(Keyword.get(opts, :provider)),
         result <- Harness.cancel(provider, session_id) do
      normalize_cancel_result(result, provider)
    end
  end

  def cancel(_token, _opts) do
    {:error,
     Error.Backend.ExecutionFailed.exception(
       backend: id(),
       kind: :cancelled,
       message: "Harness cancellation requires a provider and non-empty session_id"
     )}
  end

  @doc """
  Runs a harness-backed request while emitting canonical backend events.
  """
  @spec run_stream(Request.t(), (Backend.Event.t() -> any())) :: {:ok, Result.t()} | {:error, term()}
  def run_stream(%Request{} = request, on_event) when is_function(on_event, 1) do
    request = %{request | stream?: true}

    with {:ok, context} <- prepare_request(request),
         :ok <- validate_prompt_request(context.request),
         :ok <- emit_started_event(on_event, context),
         {:ok, state} <- consume_harness_stream(context, on_event) do
      result = build_result(context, state)
      emit_terminal_events(on_event, context.request, result)
      {:ok, result}
    end
  end

  defp prepare_request(%Request{} = request) do
    with {:ok, request} <- validate_request(request),
         {:ok, provider} <- resolve_provider(request),
         {:ok, provider_capabilities} <- resolve_provider_capabilities(provider),
         {:ok, run_request} <- build_run_request(request, provider),
         {:ok, run_opts} <- build_run_opts(request) do
      {:ok,
       %{
         request: request,
         provider: provider,
         run_request: run_request,
         run_opts: run_opts,
         provider_capabilities: provider_capabilities
       }}
    end
  end

  defp validate_request(%Request{} = request) do
    case Backend.validate_request(__MODULE__, request) do
      :ok -> {:ok, request}
      {:error, _} = error -> error
    end
  end

  defp validate_prompt_request(%Request{prompt: prompt}) when is_binary(prompt) and prompt != "", do: :ok

  defp validate_prompt_request(%Request{}) do
    {:error, Error.Validation.Invalid.exception(message: "prompt is required", field: "prompt")}
  end

  defp resolve_provider(%Request{} = request) do
    config = Backends.config_for(id())

    request
    |> metadata_value(:provider)
    |> case do
      nil -> config[:provider]
      provider -> provider
    end
    |> normalize_provider()
  end

  defp normalize_provider(provider) when is_atom(provider), do: {:ok, provider}

  defp normalize_provider(provider) when is_binary(provider) do
    provider = String.trim(provider)

    if provider == "" do
      {:error, Error.Backend.ProviderUnavailable.exception(backend: id())}
    else
      {:ok, String.to_atom(provider)}
    end
  end

  defp normalize_provider(_provider), do: {:error, Error.Backend.ProviderUnavailable.exception(backend: id())}

  defp resolve_provider_capabilities(provider) do
    case Harness.capabilities(provider) do
      {:ok, %HarnessCapabilities{} = capabilities} -> {:ok, capabilities}
      {:error, _reason} -> {:ok, nil}
    end
  end

  defp build_run_request(%Request{} = request, provider) when is_atom(provider) do
    defaults = request_defaults()

    attrs = %{
      prompt: request.prompt,
      cwd: workspace_cwd(request, defaults),
      model: harness_model(request, defaults),
      max_turns: request_max_turns(request, defaults),
      timeout_ms: request.timeout_ms || defaults_value(defaults, :timeout_ms),
      system_prompt: request.system_prompt || defaults_value(defaults, :system_prompt),
      allowed_tools: allowed_tools(request, defaults),
      attachments: attachments(request, defaults),
      metadata: request_metadata(request, provider, defaults)
    }

    case HarnessRunRequest.new(attrs) do
      {:ok, %HarnessRunRequest{} = run_request} ->
        {:ok, run_request}

      {:error, reason} ->
        {:error,
         Error.Validation.Invalid.exception(
           message: "invalid harness request: #{inspect(reason)}",
           field: "run_request"
         )}
    end
  end

  defp build_run_opts(%Request{} = request) do
    config = Backends.config_for(id())
    configured = normalize_keyword(config[:run_opts])
    request_scoped = request |> metadata_value(:run_opts) |> normalize_keyword()
    {:ok, Keyword.merge(configured, request_scoped)}
  end

  defp request_defaults do
    config = Backends.config_for(id())

    case config[:request_defaults] do
      %{} = defaults -> defaults
      defaults when is_list(defaults) -> Map.new(defaults)
      _ -> %{}
    end
  end

  defp workspace_cwd(%Request{workspace: %Request.Workspace{cwd: cwd}}, _defaults) when is_binary(cwd) and cwd != "",
    do: cwd

  defp workspace_cwd(_request, defaults), do: normalize_optional_string(defaults_value(defaults, :cwd))

  defp harness_model(%Request{model: nil}, defaults), do: normalize_optional_string(defaults_value(defaults, :model))
  defp harness_model(%Request{model: model}, _defaults) when is_binary(model), do: normalize_optional_string(model)
  defp harness_model(%Request{model: model}, _defaults), do: Jido.AI.model_label(model)

  defp request_max_turns(%Request{} = request, defaults) do
    request |> metadata_value(:max_turns) |> normalize_optional_integer() ||
      normalize_optional_integer(defaults_value(defaults, :max_turns))
  end

  defp allowed_tools(%Request{} = request, defaults) do
    default_tools = defaults |> defaults_value(:allowed_tools) |> normalize_allowed_tools() || []
    request_tools = request |> metadata_value(:allowed_tools) |> normalize_allowed_tools() || []

    case Enum.uniq(default_tools ++ request_tools) do
      [] -> nil
      allowed_tools -> allowed_tools
    end
  end

  defp attachments(%Request{workspace: %Request.Workspace{attachments: attachments}}, _defaults)
       when is_list(attachments) and attachments != [] do
    attachments
    |> Enum.map(&normalize_attachment!/1)
    |> Enum.reject(&is_nil/1)
  end

  defp attachments(_request, defaults) do
    defaults
    |> defaults_value(:attachments)
    |> normalize_default_attachments()
  end

  defp request_metadata(%Request{} = request, provider, defaults) when is_atom(provider) do
    default_metadata =
      defaults
      |> defaults_value(:metadata)
      |> stringify_map_keys()

    backend_metadata =
      request
      |> metadata_value(:metadata)
      |> stringify_map_keys()

    request_metadata = stringify_map_keys(request.metadata)
    workspace_metadata = workspace_metadata(request)

    default_metadata
    |> Map.merge(workspace_metadata)
    |> Map.merge(request_metadata)
    |> Map.merge(backend_metadata)
    |> put_if_present("request_id", request.request_id)
    |> put_if_present("session_id", workspace_session_id(request))
    |> Map.put("backend", Atom.to_string(id()))
    |> Map.put("provider", Atom.to_string(provider))
    |> Map.put("operation", Atom.to_string(request.operation))
  end

  defp workspace_metadata(%Request{workspace: %Request.Workspace{metadata: metadata}}) when is_map(metadata) do
    stringify_map_keys(metadata)
  end

  defp workspace_metadata(_request), do: %{}

  defp workspace_session_id(%Request{workspace: %Request.Workspace{session_id: session_id}})
       when is_binary(session_id) and session_id != "" do
    session_id
  end

  defp workspace_session_id(_request), do: nil

  defp run_harness_request(%{provider: provider, run_request: %HarnessRunRequest{} = run_request, run_opts: run_opts}) do
    case Harness.run_request(provider, run_request, run_opts) do
      {:ok, stream} -> {:ok, stream}
      {:error, reason} -> {:error, wrap_harness_error(provider, reason)}
    end
  end

  defp consume_harness_stream(%{request: %Request{} = request} = context, on_event) do
    with {:ok, stream} <- run_harness_request(context) do
      Enum.reduce_while(stream, {:ok, initial_state(context)}, fn %HarnessEvent{} = event, {:ok, state} ->
        next_state = note_harness_event(state, event)

        case translate_harness_event(context, next_state, event) do
          {:ok, translated, translated_state} ->
            emit_translated_events(on_event, request, translated)
            {:cont, {:ok, translated_state}}

          {:error, reason, translated} ->
            emit_translated_events(on_event, request, translated)
            {:halt, {:error, wrap_harness_error(context.provider, reason)}}
        end
      end)
    end
  end

  defp build_event_stream(%{request: %Request{} = request} = context, stream) do
    started = emit_started_event_data(context)

    Stream.concat(
      [started],
      Stream.transform(stream, initial_state(context), fn
        %HarnessEvent{} = event, state ->
          next_state = note_harness_event(state, event)

          case translate_harness_event(context, next_state, event) do
            {:ok, translated, translated_state} ->
              {translated, translated_state}

            {:error, reason, translated} ->
              failed =
                backend_event(
                  request,
                  :failed,
                  %{error: wrap_harness_error(context.provider, reason), provider: context.provider},
                  reason
                )

              {translated ++ [failed], next_state}
          end
      end)
    )
  end

  defp initial_state(%{run_request: %HarnessRunRequest{} = run_request, provider: provider}) do
    %{
      provider: provider,
      model: result_model(provider, run_request.model),
      session_id: nil,
      timestamp: nil,
      text_parts: [],
      thinking_parts: [],
      tool_calls: [],
      usage: nil,
      finish_reason: nil,
      completed_payload: %{},
      metadata: %{},
      raw_events: []
    }
  end

  defp note_harness_event(state, %HarnessEvent{} = event) do
    payload = normalize_payload(event.payload)

    session_id =
      case normalize_optional_string(event.session_id) do
        nil -> state.session_id
        value -> value
      end

    timestamp =
      case normalize_optional_string(event.timestamp) do
        nil -> state.timestamp
        value -> value
      end

    %{
      state
      | session_id: session_id,
        timestamp: timestamp,
        raw_events: [event | state.raw_events],
        metadata: Map.merge(state.metadata, normalize_payload(Map.get(payload, "metadata", %{})))
    }
  end

  defp emit_started_event(on_event, context) do
    on_event.(emit_started_event_data(context))
    :ok
  end

  defp emit_started_event_data(%{
         request: %Request{} = request,
         provider: provider,
         run_request: %HarnessRunRequest{} = run_request
       }) do
    backend_event(
      request,
      :started,
      %{
        model: run_request.model,
        provider: provider,
        cwd: run_request.cwd,
        attachment_count: length(run_request.attachments),
        allowed_tools: run_request.allowed_tools,
        control: cancel_control(provider, workspace_session_id(request), nil)
      }
      |> drop_nil_values(),
      run_request
    )
  end

  defp emit_terminal_events(on_event, %Request{} = request, %Result{} = result) do
    if is_map(result.usage) do
      emit_usage_event(on_event, request, result)
    end

    on_event.(backend_event(request, :completed, %{result: result}, result.raw))
    :ok
  end

  defp emit_usage_event(on_event, %Request{} = request, %Result{} = result) do
    on_event.(backend_event(request, :usage, %{usage: result.usage, model: result.model}, result.usage))
  end

  defp translate_harness_event(context, state, %HarnessEvent{} = event) do
    payload = normalize_payload(event.payload)
    type = event.type
    translated = maybe_session_metadata_event(context, state, event)

    cond do
      type in @delta_event_types ->
        delta = extract_text_delta(payload)
        updated_state = append_text(state, delta)
        {:ok, translated ++ maybe_delta_event(context.request, delta, :delta, event), updated_state}

      type in @thinking_event_types ->
        delta = extract_thinking_delta(payload)
        updated_state = append_thinking(state, delta)
        {:ok, translated ++ maybe_delta_event(context.request, delta, :thinking, event), updated_state}

      type in @tool_call_event_types ->
        tool_call = extract_tool_call(payload)
        updated_state = %{state | tool_calls: state.tool_calls ++ [tool_call]}

        {:ok,
         translated ++
           [
             backend_event(
               context.request,
               :tool_call,
               Map.merge(tool_call, %{provider: context.provider, session_id: state.session_id}) |> drop_nil_values(),
               event
             )
           ], updated_state}

      type in @tool_result_event_types ->
        {:ok,
         translated ++
           [
             backend_event(
               context.request,
               :tool_result,
               extract_tool_result(payload)
               |> Map.merge(%{provider: context.provider, session_id: state.session_id})
               |> drop_nil_values(),
               event
             )
           ], state}

      type == :usage ->
        usage = normalize_usage(payload)

        {:ok, translated ++ [backend_event(context.request, :usage, %{usage: usage, model: state.model}, event)],
         %{state | usage: usage}}

      type in @completed_event_types ->
        completed_payload = payload
        finish_reason = Map.get(payload, "finish_reason") || Map.get(payload, :finish_reason)

        completed_state =
          state
          |> append_text(extract_final_text(payload))
          |> Map.put(:finish_reason, finish_reason)
          |> Map.put(:completed_payload, completed_payload)

        {:ok, translated, completed_state}

      type in @cancelled_event_types ->
        error =
          Error.Backend.ExecutionFailed.exception(
            backend: id(),
            provider: context.provider,
            kind: :cancelled,
            reason: payload
          )

        {:error, error,
         translated ++
           [backend_event(context.request, :cancelled, %{reason: payload, provider: context.provider}, event)]}

      type in @failed_event_types ->
        error = Error.Backend.ExecutionFailed.exception(backend: id(), provider: context.provider, reason: payload)

        {:error, error,
         translated ++ [backend_event(context.request, :failed, %{error: error, provider: context.provider}, event)]}

      type in @metadata_event_types ->
        {:ok, translated, state}

      true ->
        {:ok,
         translated ++
           [
             backend_event(
               context.request,
               :metadata,
               %{event_type: type, provider: context.provider, payload: payload},
               event
             )
           ], state}
    end
  end

  defp maybe_session_metadata_event(
         %{request: %Request{} = request, provider: provider, provider_capabilities: caps},
         state,
         %HarnessEvent{} = event
       ) do
    session_id = normalize_optional_string(event.session_id)
    timestamp = normalize_optional_string(event.timestamp)

    if session_id in [nil, state.session_id] and is_nil(timestamp) do
      []
    else
      [
        backend_event(
          request,
          :metadata,
          %{
            provider: provider,
            session_id: session_id || state.session_id,
            timestamp: timestamp || state.timestamp,
            control: cancel_control(provider, session_id || state.session_id, caps)
          }
          |> drop_nil_values(),
          event
        )
      ]
    end
  end

  defp cancel_control(_provider, nil, _caps), do: nil

  defp cancel_control(provider, session_id, %HarnessCapabilities{cancellation?: true})
       when is_atom(provider) and is_binary(session_id) do
    %{cancel: fn -> Harness.cancel(provider, session_id) end}
  end

  defp cancel_control(_provider, _session_id, _caps), do: nil

  defp maybe_delta_event(_request, nil, _kind, _raw), do: []
  defp maybe_delta_event(_request, "", _kind, _raw), do: []

  defp maybe_delta_event(%Request{} = request, delta, kind, raw) when kind in [:delta, :thinking] do
    [
      backend_event(
        request,
        kind,
        %{
          delta: delta,
          chunk_type: if(kind == :delta, do: :content, else: :thinking)
        },
        raw
      )
    ]
  end

  defp append_text(state, nil), do: state
  defp append_text(state, ""), do: state
  defp append_text(state, text), do: %{state | text_parts: state.text_parts ++ [text]}

  defp append_thinking(state, nil), do: state
  defp append_thinking(state, ""), do: state
  defp append_thinking(state, text), do: %{state | thinking_parts: state.thinking_parts ++ [text]}

  defp build_result(%{provider: provider, run_request: %HarnessRunRequest{} = run_request}, state) do
    text = final_text(state)
    thinking = final_thinking(state)

    Result.new(
      backend: id(),
      operation: :text,
      content: text,
      text: text,
      thinking_content: thinking,
      tool_calls: state.tool_calls,
      usage: state.usage,
      model: state.model || result_model(provider, run_request.model),
      finish_reason: state.finish_reason,
      message_metadata:
        %{
          provider: provider,
          session_id: state.session_id,
          timestamp: state.timestamp
        }
        |> drop_nil_values(),
      metadata:
        %{
          provider: provider,
          session_id: state.session_id,
          timestamp: state.timestamp
        }
        |> Map.merge(state.metadata)
        |> drop_nil_values(),
      raw: %{
        provider: provider,
        session_id: state.session_id,
        completed_payload: state.completed_payload,
        event_count: length(state.raw_events)
      }
    )
  end

  defp final_text(%{completed_payload: payload} = state) when map_size(payload) > 0 do
    extract_final_text(payload) || Enum.join(state.text_parts)
  end

  defp final_text(state), do: Enum.join(state.text_parts)
  defp final_thinking(state), do: state.thinking_parts |> Enum.join() |> normalize_optional_string()

  defp result_model(provider, model) when is_binary(model) do
    case String.trim(model) do
      "" -> Atom.to_string(provider)
      normalized -> normalized
    end
  end

  defp result_model(provider, nil), do: Atom.to_string(provider)

  defp result_model(provider, model),
    do: normalize_optional_string(Jido.AI.model_label(model)) || Atom.to_string(provider)

  defp wrap_harness_error(provider, %Jido.Harness.Error.ProviderNotFoundError{} = error) do
    Error.Backend.ProviderUnavailable.exception(
      backend: id(),
      provider: provider,
      message: Exception.message(error)
    )
  end

  defp wrap_harness_error(_provider, %Jido.Harness.Error.InvalidInputError{} = error) do
    Error.Validation.Invalid.exception(message: Exception.message(error))
  end

  defp wrap_harness_error(provider, %Jido.Harness.Error.ExecutionFailureError{} = error) do
    Error.Backend.ExecutionFailed.exception(
      backend: id(),
      provider: provider,
      reason: error,
      message: Exception.message(error)
    )
  end

  defp wrap_harness_error(provider, %Error.Backend.ExecutionFailed{} = error) when provider != nil, do: error
  defp wrap_harness_error(_provider, %Error.Validation.Invalid{} = error), do: error
  defp wrap_harness_error(_provider, %Error.Backend.ProviderUnavailable{} = error), do: error

  defp wrap_harness_error(provider, reason) do
    Error.Backend.ExecutionFailed.exception(backend: id(), provider: provider, reason: reason)
  end

  defp normalize_cancel_result(:ok, _provider), do: :ok
  defp normalize_cancel_result({:ok, _} = ok, _provider), do: ok

  defp normalize_cancel_result({:error, reason}, provider) do
    {:error, wrap_harness_error(provider, reason)}
  end

  defp normalize_cancel_result(other, provider), do: {:error, wrap_harness_error(provider, other)}

  defp emit_translated_events(nil, _request, _events), do: :ok

  defp emit_translated_events(on_event, _request, events) when is_function(on_event, 1) do
    Enum.each(events, on_event)
  end

  defp backend_event(%Request{} = request, kind, data, raw) do
    Event.new(%{
      backend: id(),
      request_id: request.request_id,
      operation: request.operation,
      kind: kind,
      data: data,
      raw: raw
    })
  end

  defp extract_text_delta(payload) do
    payload["delta"] || payload["text"] || payload["content"] || payload[:delta] || payload[:text] || payload[:content]
  end

  defp extract_thinking_delta(payload) do
    payload["delta"] || payload["thinking"] || payload["reasoning"] || payload[:delta] || payload[:thinking] ||
      payload[:reasoning]
  end

  defp extract_final_text(payload) do
    payload["text"] || payload["content"] || payload["result"] || payload[:text] || payload[:content] ||
      payload[:result]
  end

  defp extract_tool_call(payload) do
    %{
      id: payload["id"] || payload[:id],
      name: payload["name"] || payload[:name] || payload["tool"] || payload[:tool],
      arguments: payload["arguments"] || payload[:arguments] || payload["args"] || payload[:args] || %{}
    }
    |> drop_nil_values()
  end

  defp extract_tool_result(payload) do
    %{
      id: payload["id"] || payload[:id],
      name: payload["name"] || payload[:name] || payload["tool"] || payload[:tool],
      result: payload["result"] || payload[:result] || payload["content"] || payload[:content]
    }
    |> drop_nil_values()
  end

  defp normalize_usage(payload) when is_map(payload) do
    input_tokens = Map.get(payload, "input_tokens", Map.get(payload, :input_tokens, 0))
    output_tokens = Map.get(payload, "output_tokens", Map.get(payload, :output_tokens, 0))
    total_tokens = Map.get(payload, "total_tokens", Map.get(payload, :total_tokens, input_tokens + output_tokens))

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens
    }
  end

  defp normalize_usage(_payload), do: nil

  defp normalize_default_attachments(nil), do: []

  defp normalize_default_attachments(attachments) when is_list(attachments) do
    attachments
    |> Enum.map(&normalize_attachment!/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_default_attachments(_attachments), do: []

  defp normalize_attachment!(attachment) when is_binary(attachment), do: normalize_optional_string(attachment)

  defp normalize_attachment!(%{} = attachment) do
    attachment[:path] || attachment["path"] || attachment[:file] || attachment["file"] || attachment[:name] ||
      attachment["name"]
  end

  defp normalize_attachment!(attachment) do
    raise ArgumentError, "invalid harness attachment: #{inspect(attachment)}"
  end

  defp normalize_allowed_tools(nil), do: nil

  defp normalize_allowed_tools(allowed_tools) when is_list(allowed_tools) do
    allowed_tools
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      tools -> tools
    end
  end

  defp normalize_allowed_tools(_allowed_tools), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(_value), do: nil

  defp normalize_keyword(value) when is_list(value), do: value
  defp normalize_keyword(%{} = value), do: Enum.to_list(value)
  defp normalize_keyword(_value), do: []

  defp normalize_payload(%{} = payload), do: payload
  defp normalize_payload(_payload), do: %{}

  defp stringify_map_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      case stringify_key(key) do
        nil -> acc
        string_key -> Map.put(acc, string_key, value)
      end
    end)
  end

  defp stringify_map_keys(_value), do: %{}

  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(_key), do: nil

  defp metadata_value(%Request{backend_metadata: metadata}, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp defaults_value(defaults, key) when is_map(defaults) do
    Map.get(defaults, key, Map.get(defaults, Atom.to_string(key)))
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp drop_nil_values(%{} = map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
