defmodule Jido.AI.Backends.ReqLLM do
  # covers: jido_ai.core_runtime.llm_facades
  @moduledoc """
  ReqLLM-backed implementation of the internal backend contract.

  This adapter owns ReqLLM model resolution, message normalization, request
  option shaping, and normalized result projection for the default backend path.
  """

  @behaviour Jido.AI.Backend

  alias Jido.AI.Backend
  alias Jido.AI.Backend.{Capabilities, Request, Result}
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Turn
  alias ReqLLM.Context

  @type reqllm_opts :: keyword()

  @impl true
  def id, do: :req_llm

  @impl true
  def capabilities do
    Capabilities.new(
      text_generation: true,
      streaming: true,
      structured_output: true,
      embeddings: true,
      local_tools: true,
      cancellation: false,
      message_history: true,
      workspace_execution: false
    )
  end

  @impl true
  def generate(%Request{} = request) do
    with {:ok, request} <- validate_request(request),
         {:ok, model} <- resolve_model(request),
         {:ok, result} <- generate_for_operation(request, model) do
      {:ok, result}
    end
  end

  @impl true
  def stream(%Request{} = request) do
    request = %{request | stream?: true}

    with {:ok, request} <- validate_request(request),
         :ok <- ensure_text_operation(request),
         {:ok, model} <- resolve_model(request),
         {:ok, messages} <- build_messages(request),
         {:ok, stream_response} <- ReqLLM.stream_text(model, messages, build_generation_opts(request)) do
      {:ok, stream_response}
    end
  end

  @impl true
  def cancel(_token, _opts) do
    {:error,
     Jido.AI.Error.Backend.UnsupportedCapability.exception(
       backend: id(),
       capability: :cancellation,
       operation: :text
     )}
  end

  @doc """
  Returns the raw transport payload from a normalized result.
  """
  @spec raw_result(Result.t()) :: term()
  def raw_result(%Result{} = result), do: result.raw

  @doc """
  Returns the adapter-shaped generation options for a request.
  """
  @spec generation_opts(Request.t()) :: keyword()
  def generation_opts(%Request{} = request), do: build_generation_opts(request)

  defp generate_for_operation(%Request{operation: :text} = request, model) do
    with {:ok, messages} <- build_messages(request),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, build_generation_opts(request)) do
      {:ok, normalize_text_result(response, model)}
    end
  end

  defp generate_for_operation(%Request{operation: :object, response_schema: nil}, _model) do
    {:error, Jido.AI.Error.Validation.Invalid.exception(message: "object_schema is required", field: "object_schema")}
  end

  defp generate_for_operation(%Request{operation: :object} = request, model) do
    with {:ok, messages} <- build_messages(request),
         {:ok, response} <-
           ReqLLM.Generation.generate_object(
             model,
             messages,
             request.response_schema,
             build_generation_opts(request)
           ) do
      {:ok, normalize_object_result(response, model)}
    end
  end

  defp generate_for_operation(%Request{operation: :embedding} = request, model) do
    with {:ok, inputs} <- build_embedding_inputs(request),
         {:ok, response} <- ReqLLM.Embedding.embed(model, inputs, build_embedding_opts(request)) do
      {:ok, normalize_embedding_result(response, model)}
    end
  end

  defp validate_request(%Request{} = request) do
    case Backend.validate_request(__MODULE__, request) do
      :ok -> {:ok, request}
      {:error, _} = error -> error
    end
  end

  defp ensure_text_operation(%Request{operation: :text}), do: :ok

  defp ensure_text_operation(%Request{operation: operation}) do
    {:error,
     Jido.AI.Error.Backend.UnsupportedCapability.exception(
       backend: id(),
       capability: :streaming,
       operation: operation
     )}
  end

  defp resolve_model(%Request{model: nil}) do
    {:error, Jido.AI.Error.Validation.Invalid.exception(message: "model is required", field: "model")}
  rescue
    _ -> {:error, :invalid_model_format}
  end

  defp resolve_model(%Request{model: model}) do
    {:ok, Jido.AI.resolve_model(model)}
  rescue
    ArgumentError -> {:error, :invalid_model_format}
  end

  defp build_messages(%Request{messages: [_ | _] = messages, system_prompt: nil}), do: {:ok, messages}
  defp build_messages(%Request{messages: [_ | _] = messages, system_prompt: ""}), do: {:ok, messages}

  defp build_messages(%Request{messages: [_ | _] = messages, system_prompt: system_prompt})
       when is_binary(system_prompt) do
    case Context.normalize(messages, system_prompt: system_prompt) do
      {:ok, req_context} -> {:ok, req_context.messages}
      {:error, _} = error -> error
    end
  end

  defp build_messages(%Request{prompt: prompt, system_prompt: nil}) when is_binary(prompt) do
    case Context.normalize(prompt, []) do
      {:ok, req_context} -> {:ok, req_context.messages}
      {:error, _} = error -> error
    end
  end

  defp build_messages(%Request{prompt: prompt, system_prompt: system_prompt})
       when is_binary(prompt) and is_binary(system_prompt) do
    case Context.normalize(prompt, system_prompt: system_prompt) do
      {:ok, req_context} -> {:ok, req_context.messages}
      {:error, _} = error -> error
    end
  end

  defp build_messages(_request) do
    {:error, Jido.AI.Error.Validation.Invalid.exception(message: "prompt or messages are required", field: "prompt")}
  end

  defp build_embedding_inputs(%Request{inputs: [_ | _] = inputs}), do: {:ok, inputs}
  defp build_embedding_inputs(%Request{prompt: prompt}) when is_binary(prompt), do: {:ok, [prompt]}

  defp build_embedding_inputs(_request) do
    {:error, Jido.AI.Error.Validation.Invalid.exception(message: "embedding inputs are required", field: "inputs")}
  end

  defp build_generation_opts(%Request{} = request) do
    []
    |> maybe_put_opt(:max_tokens, request.max_tokens)
    |> maybe_put_opt(:temperature, request.temperature)
    |> maybe_put_timeout(request.timeout_ms)
    |> maybe_put_req_http_options(metadata_value(request, :req_http_options))
    |> maybe_put_tools(request.tool_intent)
    |> maybe_put_tool_choice(request.tool_intent)
    |> merge_extra_opts(metadata_value(request, :opts))
  end

  defp build_embedding_opts(%Request{} = request) do
    []
    |> maybe_put_timeout(request.timeout_ms)
    |> maybe_put_req_http_options(metadata_value(request, :req_http_options))
    |> maybe_put_opt(:dimensions, metadata_value(request, :dimensions))
    |> merge_extra_opts(metadata_value(request, :opts))
  end

  defp normalize_text_result(response, model) do
    turn = Turn.from_response(response, model: result_model(response, model))

    Result.new(
      backend: id(),
      operation: :text,
      content: response_content(response),
      text: turn.text,
      tool_calls: turn.tool_calls,
      usage: normalize_usage(turn.usage),
      model: turn.model,
      finish_reason: turn.finish_reason,
      message_metadata: turn.message_metadata,
      raw: response
    )
  end

  defp normalize_object_result(response, model) do
    Result.new(
      backend: id(),
      operation: :object,
      object: map_or_nil(response, :object),
      usage: normalize_usage(map_or_nil(response, :usage)),
      model: normalize_optional_string(map_or_nil(response, :model)) || Jido.AI.model_label(model),
      metadata: %{},
      raw: response
    )
  end

  defp normalize_embedding_result(response, model) do
    embeddings = extract_embeddings(response)

    Result.new(
      backend: id(),
      operation: :embedding,
      embeddings: embeddings,
      model: embedding_model(response, model),
      metadata: %{count: length(embeddings), dimensions: embedding_dimensions(embeddings)},
      raw: response
    )
  end

  defp response_content(%ReqLLM.Response{} = response), do: response.message && response.message.content
  defp response_content(%{message: %{content: content}}), do: content
  defp response_content(_), do: nil

  defp result_model(response, model) do
    normalize_optional_string(map_or_nil(response, :model)) || Jido.AI.model_label(model)
  end

  defp embedding_model(response, model) do
    normalize_optional_string(map_or_nil(response, :model)) || Jido.AI.model_label(model)
  end

  defp embedding_dimensions([]), do: 0
  defp embedding_dimensions([embedding | _]) when is_list(embedding), do: length(embedding)
  defp embedding_dimensions(_), do: 0

  defp extract_embeddings(embeddings) when is_list(embeddings), do: embeddings
  defp extract_embeddings(%{embeddings: embeddings}) when is_list(embeddings), do: embeddings
  defp extract_embeddings(%{"embeddings" => embeddings}) when is_list(embeddings), do: embeddings
  defp extract_embeddings(%{data: data}) when is_list(data), do: Enum.map(data, &extract_embedding_vector/1)
  defp extract_embeddings(%{"data" => data}) when is_list(data), do: Enum.map(data, &extract_embedding_vector/1)
  defp extract_embeddings(_), do: []

  defp extract_embedding_vector(%{embedding: embedding}) when is_list(embedding), do: embedding
  defp extract_embedding_vector(%{"embedding" => embedding}) when is_list(embedding), do: embedding
  defp extract_embedding_vector(other) when is_list(other), do: other
  defp extract_embedding_vector(_), do: []

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, _key, ""), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_timeout(opts, nil), do: opts
  defp maybe_put_timeout(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)

  defp maybe_put_req_http_options(opts, req_http_options) when is_list(req_http_options) and req_http_options != [] do
    Keyword.put(opts, :req_http_options, req_http_options)
  end

  defp maybe_put_req_http_options(opts, _), do: opts

  defp maybe_put_tools(opts, %Request.ToolIntent{tools: nil}), do: opts
  defp maybe_put_tools(opts, %Request.ToolIntent{tools: []}), do: opts

  defp maybe_put_tools(opts, %Request.ToolIntent{tools: tools}) do
    Keyword.put(opts, :tools, normalize_reqllm_tools(tools))
  end

  defp maybe_put_tools(opts, _), do: opts

  defp maybe_put_tool_choice(opts, %Request.ToolIntent{tool_choice: nil}), do: opts

  defp maybe_put_tool_choice(opts, %Request.ToolIntent{tool_choice: tool_choice}),
    do: Keyword.put(opts, :tool_choice, tool_choice)

  defp maybe_put_tool_choice(opts, _), do: opts

  defp merge_extra_opts(opts, extra_opts) when is_list(extra_opts), do: Keyword.merge(opts, extra_opts)
  defp merge_extra_opts(opts, extra_opts) when is_map(extra_opts), do: Keyword.merge(opts, Enum.to_list(extra_opts))
  defp merge_extra_opts(opts, _), do: opts

  defp normalize_reqllm_tools(tools) when is_list(tools) do
    cond do
      tools == [] ->
        []

      Enum.all?(tools, &reqllm_tool?/1) ->
        tools

      true ->
        ToolAdapter.from_actions(tools)
    end
  end

  defp normalize_reqllm_tools(tools) when is_map(tools) do
    tools |> Map.values() |> ToolAdapter.from_actions()
  end

  defp normalize_reqllm_tools(tool) when is_atom(tool) do
    [ToolAdapter.from_action(tool)]
  end

  defp normalize_reqllm_tools(other), do: other

  defp reqllm_tool?(%ReqLLM.Tool{}), do: true
  defp reqllm_tool?(%{name: _name, function: _function}), do: true
  defp reqllm_tool?(_), do: false

  defp metadata_value(%Request{backend_metadata: metadata}, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp map_or_nil(%{} = map, key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_or_nil(_, _key), do: nil

  defp normalize_usage(%{} = usage) do
    input_tokens = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") || 0
    output_tokens = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") || 0
    total_tokens = Map.get(usage, :total_tokens) || Map.get(usage, "total_tokens") || input_tokens + output_tokens

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens
    }
  end

  defp normalize_usage(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil
end
