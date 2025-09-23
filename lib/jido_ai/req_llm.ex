defmodule Jido.AI.ReqLLM do
  @moduledoc """
  Bridge module for integrating ReqLLM with Jido AI.

  This module provides the translation layer between Jido AI's current interfaces
  and ReqLLM's API, ensuring seamless interoperability while preserving backward
  compatibility.

  Key responsibilities:
  - Message format conversion between Jido AI and ReqLLM
  - Error mapping to preserve existing error structures
  - Response shape transformation to maintain API contracts
  - Logging integration preservation
  """

  require Logger

  @doc """
  Converts Jido AI message format to ReqLLM context format.

  ReqLLM supports both string prompts and message structures. This function
  converts Jido AI's message format to the appropriate ReqLLM format.

  ## Parameters
    - messages: List of Jido AI message maps with :role and :content

  ## Returns
    - ReqLLM context or string prompt

  ## Examples

      iex> messages = [%{role: :user, content: "Hello"}]
      iex> Jido.AI.ReqLLM.convert_messages(messages)
      [%{role: :user, content: "Hello"}]
  """
  @spec convert_messages(list(map())) :: list(map()) | String.t()
  def convert_messages([%{role: :user, content: content}]) do
    # For simple single user messages, use string format
    content
  end

  def convert_messages(messages) when is_list(messages) do
    # For complex conversations, use message format
    Enum.map(messages, &convert_message/1)
  end

  @doc """
  Converts a single Jido AI message to ReqLLM message format.

  ## Parameters
    - message: Map with :role and :content keys

  ## Returns
    - Map in ReqLLM message format
  """
  @spec convert_message(map()) :: map()
  def convert_message(%{role: role, content: content}) do
    %{role: role, content: content}
  end

  @doc """
  Converts ReqLLM response to Jido AI response format.

  Preserves the existing response structure that Jido AI consumers expect.

  ## Parameters
    - response: ReqLLM response (map or struct)

  ## Returns
    - Map in Jido AI response format
  """
  @spec convert_response(map() | struct()) :: map()
  def convert_response(response) when is_map(response) do
    %{
      content: get_response_text(response),
      usage: convert_usage(response[:usage] || response["usage"]),
      tool_calls: convert_tool_calls(response[:tool_calls] || response["tool_calls"] || []),
      finish_reason: response[:finish_reason] || response["finish_reason"]
    }
  end

  @doc """
  Maps ReqLLM errors to Jido AI error format.

  Preserves existing `{:ok, result} | {:error, reason}` patterns and error structures.

  ## Parameters
    - error: ReqLLM error term

  ## Returns
    - Jido AI compatible error term
  """
  @spec map_error(term()) :: {:error, term()}
  def map_error({:error, %{status: status, body: body}}) do
    {:error, %{
      reason: "http_error",
      details: "HTTP #{status}: #{inspect(body)}",
      status: status,
      body: body
    }}
  end

  def map_error({:error, %{__struct__: struct_name} = error}) when is_atom(struct_name) do
    # Handle ReqLLM struct errors
    {:error, %{
      reason: Map.get(error, :reason, "req_llm_error"),
      details: Map.get(error, :message, inspect(error)),
      original_error: error
    }}
  end

  def map_error({:error, error}) when is_map(error) do
    {:error, %{
      reason: error[:type] || error["type"] || "req_llm_error",
      details: error[:message] || error["message"] || inspect(error),
      original_error: error
    }}
  end

  def map_error({:error, %Req.TransportError{} = error}) do
    {:error, %{
      reason: "transport_error",
      details: Exception.message(error),
      original_error: error
    }}
  end

  def map_error({:error, reason}) when is_binary(reason) do
    {:error, %{
      reason: "req_llm_error",
      details: reason
    }}
  end

  def map_error({:error, reason}) do
    {:error, %{
      reason: "unknown_error",
      details: inspect(reason),
      original_error: reason
    }}
  end

  def map_error(other) do
    {:error, %{
      reason: "unexpected_error",
      details: "Unexpected error format: #{inspect(other)}",
      original_error: other
    }}
  end

  @doc """
  Builds ReqLLM request options from Jido AI parameters.

  Maps Jido AI parameters to ReqLLM's expected option format.

  ## Parameters
    - params: Map of Jido AI parameters

  ## Returns
    - Map of ReqLLM options
  """
  @spec build_req_llm_options(map()) :: map()
  def build_req_llm_options(params) do
    params
    |> Map.take([:temperature, :max_tokens, :top_p, :stop, :tools, :tool_choice])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Converts Jido AI tools to ReqLLM tool format.

  ## Parameters
    - tools: List of Jido Action modules

  ## Returns
    - {:ok, list(ReqLLM.Tool.t())} on success
    - {:error, reason} on failure
  """
  @spec convert_tools(list(module())) :: {:ok, list(ReqLLM.Tool.t())} | {:error, term()}
  def convert_tools(tools) when is_list(tools) do
    try do
      converted_tools = Enum.map(tools, &convert_tool/1)
      {:ok, converted_tools}
    rescue
      error ->
        {:error, %{
          reason: "tool_conversion_error",
          details: Exception.message(error),
          original_error: error
        }}
    end
  end

  @doc """
  Converts ReqLLM streaming response to Jido AI streaming format.

  Transforms a ReqLLM streaming response into the expected chunk format
  for Jido AI consumers, maintaining backward compatibility.

  ## Parameters
    - stream: ReqLLM streaming response (enumerable of chunks)
    - opts: Conversion options (optional)
      - :enhanced - Use enhanced streaming adapter (default: false)
      - Other options passed to StreamingAdapter if enhanced mode enabled

  ## Returns
    - Transformed stream with Jido AI compatible chunk format
  """
  @spec convert_streaming_response(Enumerable.t(), keyword()) :: Enumerable.t()
  def convert_streaming_response(stream, opts \\ []) do
    if Keyword.get(opts, :enhanced, false) do
      # Use enhanced streaming adapter for advanced functionality
      Jido.AI.ReqLLM.StreamingAdapter.adapt_stream(stream, opts)
    else
      # Use basic transformation for backward compatibility
      Stream.map(stream, &transform_streaming_chunk/1)
    end
  end

  @doc """
  Transforms a single ReqLLM streaming chunk to Jido AI format.

  Converts individual streaming chunks from ReqLLM format to the format
  expected by Jido AI consumers.

  ## Parameters
    - chunk: ReqLLM streaming chunk (map or struct)

  ## Returns
    - Map in Jido AI streaming chunk format
  """
  @spec transform_streaming_chunk(map() | struct()) :: map()
  def transform_streaming_chunk(chunk) when is_map(chunk) do
    %{
      content: get_chunk_content(chunk),
      finish_reason: chunk[:finish_reason] || chunk["finish_reason"],
      usage: convert_usage(chunk[:usage] || chunk["usage"]),
      tool_calls: convert_tool_calls(chunk[:tool_calls] || chunk["tool_calls"] || []),
      delta: %{
        content: get_chunk_content(chunk),
        role: chunk[:role] || chunk["role"] || "assistant"
      }
    }
  end

  @doc """
  Maps ReqLLM streaming errors to Jido AI error format.

  Handles streaming-specific errors and maps them to the error format
  expected by Jido AI consumers.

  ## Parameters
    - error: ReqLLM streaming error term

  ## Returns
    - Jido AI compatible error term
  """
  @spec map_streaming_error(term()) :: {:error, term()}
  def map_streaming_error({:error, %{reason: "stream_error"} = error}) do
    {:error, %{
      reason: "streaming_error",
      details: "Streaming failed: #{error.message || inspect(error)}",
      original_error: error
    }}
  end

  def map_streaming_error({:error, %{reason: "timeout"} = error}) do
    {:error, %{
      reason: "streaming_timeout",
      details: "Stream timed out: #{error.message || inspect(error)}",
      original_error: error
    }}
  end

  def map_streaming_error(error) do
    # Fall back to regular error mapping for non-streaming errors
    map_error(error)
  end

  @doc """
  Logs ReqLLM operations preserving Jido AI's opt-in logging behavior.

  Only logs when explicitly enabled, maintaining the current minimal logging approach.

  ## Parameters
    - level: Log level (:debug, :info, :warning, :error)
    - message: Log message
    - metadata: Additional metadata (optional)
  """
  @spec log_operation(atom(), String.t(), keyword()) :: :ok
  def log_operation(level, message, metadata \\ []) do
    # Only log if explicitly enabled via configuration
    if Application.get_env(:jido_ai, :enable_req_llm_logging, false) do
      Logger.log(level, "[ReqLLM Bridge] #{message}",
        Keyword.merge([module: __MODULE__], metadata))
    end
    :ok
  end

  # Private helper functions

  defp get_response_text(response) do
    response[:text] || response["text"] ||
    response[:content] || response["content"] ||
    response[:message] || response["message"] ||
    ""
  end

  defp get_chunk_content(chunk) do
    # Extract content from streaming chunk
    chunk[:content] || chunk["content"] ||
    chunk[:text] || chunk["text"] ||
    chunk[:delta][:content] || chunk["delta"]["content"] ||
    ""
  end

  defp convert_usage(nil), do: nil
  defp convert_usage(usage) when is_map(usage) do
    # Map ReqLLM usage format to Jido AI expected format
    %{
      prompt_tokens: usage[:prompt_tokens] || usage["prompt_tokens"],
      completion_tokens: usage[:completion_tokens] || usage["completion_tokens"],
      total_tokens: usage[:total_tokens] || usage["total_tokens"]
    }
  end

  defp convert_tool_calls(nil), do: []
  defp convert_tool_calls([]), do: []
  defp convert_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &convert_tool_call/1)
  end

  defp convert_tool_call(tool_call) when is_map(tool_call) do
    %{
      id: tool_call[:id] || tool_call["id"],
      type: tool_call[:type] || tool_call["type"] || "function",
      function: %{
        name: tool_call[:function][:name] || tool_call["function"]["name"],
        arguments: tool_call[:function][:arguments] || tool_call["function"]["arguments"]
      }
    }
  end

  defp convert_tool(tool_module) when is_atom(tool_module) do
    # Convert Jido Action module to ReqLLM tool descriptor
    # Direct function calls instead of apply/2 and apply/3
    name = tool_module.name()
    description = tool_module.description()
    schema = tool_module.schema()

    ReqLLM.tool(
      name: name,
      description: description,
      parameter_schema: convert_schema_to_json_schema(schema),
      callback: fn args ->
        # Execute the Jido Action and return JSON-serializable result
        # Direct function call instead of apply/3
        case tool_module.run(args, %{}) do
          {:ok, result} -> result
          {:error, reason} -> %{error: reason}
          result -> result
        end
      end
    )
  end

  defp convert_schema_to_json_schema(schema) when is_list(schema) do
    # Convert Jido Action schema to JSON Schema format
    # This is a simplified conversion - may need enhancement for complex schemas
    properties =
      Enum.reduce(schema, %{}, fn {key, opts}, acc ->
        property = %{
          type: map_type_to_json_schema(opts[:type]),
          description: opts[:doc] || ""
        }

        property = if opts[:required], do: Map.put(property, :required, true), else: property
        property = if opts[:default], do: Map.put(property, :default, opts[:default]), else: property

        Map.put(acc, key, property)
      end)

    required_fields =
      schema
      |> Enum.filter(fn {_key, opts} -> opts[:required] end)
      |> Enum.map(fn {key, _opts} -> key end)

    %{
      type: "object",
      properties: properties,
      required: required_fields
    }
  end

  defp map_type_to_json_schema(:string), do: "string"
  defp map_type_to_json_schema(:integer), do: "integer"
  defp map_type_to_json_schema(:float), do: "number"
  defp map_type_to_json_schema(:boolean), do: "boolean"
  defp map_type_to_json_schema({:list, _inner_type}), do: "array"
  defp map_type_to_json_schema({:map, _fields}), do: "object"
  defp map_type_to_json_schema(_), do: "string"  # Default fallback
end