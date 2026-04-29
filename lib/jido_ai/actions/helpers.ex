defmodule Jido.AI.Actions.Helpers do
  # covers: jido_ai.actions.standalone_action_surface
  @moduledoc """
  Shared helper functions for Jido.AI skill actions.

  This module provides common functionality used across multiple action modules
  to reduce code duplication and ensure consistent behavior.

  ## Functions

  * `resolve_model/2` - Resolve model alias to spec
  * `build_opts/2` - Build options for LLM requests
  * `extract_text/1` - Extract text from LLM response
  * `extract_usage/1` - Extract usage information from response
  * `validate_and_sanitize_input/2` - Validate input with security checks

  ## Examples

      use Jido.AI.Actions.Helpers

      # In an action
      def run(params, _context) do
        with {:ok, model} <- resolve_model(params[:model], :fast),
             {:ok, messages} <- build_messages(params),
             opts <- build_opts(params),
             {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, opts) do
          {:ok, format_result(response)}
        end
      end
  """

  alias Jido.AI.Backend.{Request, Result}
  alias Jido.AI.Backends
  alias Jido.AI.Error.Sanitize
  alias Jido.AI.Turn
  alias Jido.AI.Validation

  @doc """
  Resolves a model parameter to a model spec.

  ## Parameters

  * `model` - Model alias or direct ReqLLM model input
  * `default` - Default model alias to use if model is nil

  ## Returns

  * `{:ok, model_input}` - Successfully resolved model
  * `{:error, :invalid_model_format}` - Invalid model format

  ## Examples

      iex> resolve_model(nil, :fast)
      {:ok, "anthropic:claude-haiku-4-5"}

      iex> resolve_model(:capable, :fast)
      {:ok, "anthropic:claude-sonnet-4-20250514"}

      iex> resolve_model("openai:gpt-4", :fast)
      {:ok, "openai:gpt-4"}
  """
  def resolve_model(nil, default), do: {:ok, Jido.AI.resolve_model(default)}

  def resolve_model(model, _default) do
    {:ok, Jido.AI.resolve_model(model)}
  rescue
    ArgumentError -> {:error, :invalid_model_format}
  end

  @doc """
  Builds ReqLLM options from action parameters.

  ## Parameters

  * `params` - Map containing :max_tokens, :temperature, :timeout keys

  ## Returns

  Keyword list of options for ReqLLM

  ## Examples

      iex> build_opts(%{max_tokens: 1000, temperature: 0.5})
      [max_tokens: 1000, temperature: 0.5]

      iex> build_opts(%{max_tokens: 1000, temperature: 0.5, timeout: 5000})
      [max_tokens: 1000, temperature: 0.5, receive_timeout: 5000]
  """
  def build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  @doc """
  Builds a backend-neutral request from action params plus explicit request attrs.
  """
  @spec build_backend_request(map(), map() | keyword()) :: Request.t()
  def build_backend_request(params, attrs) when is_map(params) do
    attrs = normalize_request_attrs(attrs)
    default_model = Map.get(attrs, :default_model)
    attrs = Map.delete(attrs, :default_model)

    workspace =
      merge_optional_maps(
        normalize_optional_map(Map.get(attrs, :workspace)),
        normalize_optional_map(Map.get(params, :workspace))
      )

    backend_metadata =
      merge_optional_maps(
        normalize_backend_metadata(Map.get(attrs, :backend_metadata)),
        normalize_backend_metadata(Map.get(params, :backend_metadata))
      )

    params
    |> Map.take([:backend, :model])
    |> Map.put(:model, Map.get(params, :model) || default_model)
    |> Map.put(:timeout_ms, params[:timeout])
    |> Map.put(:max_tokens, params[:max_tokens])
    |> Map.put(:temperature, params[:temperature])
    |> maybe_put(:workspace, workspace)
    |> Map.put(:backend_metadata, backend_metadata)
    |> Map.merge(attrs)
    |> Request.new()
  end

  @doc """
  Executes a backend-neutral generation request and returns a normalized result.
  """
  @spec generate_backend_result(map(), map() | keyword()) :: {:ok, Result.t()} | {:error, term()}
  def generate_backend_result(params, attrs) when is_map(params) do
    params
    |> build_backend_request(attrs)
    |> Backends.generate()
  end

  @doc """
  Extracts text content from an LLM response.

  Delegates to `Jido.AI.Turn.extract_text/1` which handles
  multiple response shapes consistently.

  ## Parameters

  * `response` - LLM response map

  ## Returns

  Extracted text string

  ## Examples

      iex> extract_text(%{message: %{content: "Hello"}})
      "Hello"

      iex> extract_text(%{message: %{content: [%{type: :text, text: "Hi"}]}})
      "Hi"
  """
  defdelegate extract_text(response), to: Turn

  @doc """
  Extracts usage information from an LLM response.

  ## Parameters

  * `response` - LLM response map

  ## Returns

  Map with :input_tokens, :output_tokens, :total_tokens keys

  ## Examples

      iex> extract_text(%{usage: %{input_tokens: 10, output_tokens: 20}})
      %{input_tokens: 10, output_tokens: 20, total_tokens: 30}
  """
  def extract_usage(%{usage: usage}) when is_map(usage) do
    input_tokens = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") || 0
    output_tokens = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") || 0
    total_tokens = Map.get(usage, :total_tokens) || Map.get(usage, "total_tokens") || input_tokens + output_tokens

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens
    }
  end

  def extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  @doc """
  Validates and sanitizes input parameters with security checks.

  ## Parameters

  * `params` - Map of input parameters
  * `opts` - Validation options:
    * `:required_prompt` - Whether prompt is required (default: true)
    * `:required_system_prompt` - Whether system_prompt must be validated if present
    * `:max_prompt_length` - Max length for prompt (default: Validation.max_input_length())
    * `:max_system_prompt_length` - Max length for system_prompt (default: Validation.max_prompt_length())

  ## Returns

  * `{:ok, params}` - Validation passed
  * `{:error, reason}` - Validation failed

  ## Examples

      iex> validate_and_sanitize_input(%{prompt: "Hello"})
      {:ok, %{prompt: "Hello"}}

      iex> validate_and_sanitize_input(%{prompt: ""})
      {:error, :prompt_required}
  """
  def validate_and_sanitize_input(params, opts \\ []) do
    required_prompt = Keyword.get(opts, :required_prompt, true)
    max_prompt_length = Keyword.get(opts, :max_prompt_length, Validation.max_input_length())
    max_system_prompt_length = Keyword.get(opts, :max_system_prompt_length, Validation.max_prompt_length())

    with {:ok, _prompt} <- validate_prompt_if_required(params[:prompt], required_prompt, max_prompt_length),
         {:ok, _validated} <- validate_system_prompt_if_present(params, max_system_prompt_length) do
      {:ok, params}
    else
      {:error, :empty_string} when required_prompt -> {:error, :prompt_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_prompt_if_required(nil, true, _max_length), do: {:error, :empty_string}
  defp validate_prompt_if_required("", true, _max_length), do: {:error, :empty_string}

  defp validate_prompt_if_required(prompt, true, max_length) when is_binary(prompt) do
    Validation.validate_string(prompt, max_length: max_length)
  end

  defp validate_prompt_if_required(_, false, _max_length), do: {:ok, nil}

  defp validate_system_prompt_if_present(%{system_prompt: system_prompt}, max_length) when is_binary(system_prompt) do
    Validation.validate_string(system_prompt, max_length: max_length)
  end

  defp validate_system_prompt_if_present(_params, _max_length), do: {:ok, nil}

  @doc """
  Sanitizes an error for user-facing display.

  Uses `Jido.AI.Error.Sanitize.sanitize_error_message/1` to convert
  detailed errors into generic user-safe messages.

  ## Parameters

  * `error` - The error term to sanitize

  ## Returns

  Sanitized error message string

  ## Examples

      iex> sanitize_error(%RuntimeError{message: "Internal error"})
      "An error occurred"

      iex> sanitize_error(:timeout)
      "Request timed out"
  """
  def sanitize_error(error) do
    Sanitize.sanitize_error_message(error)
  end

  @doc """
  Formats a result with error sanitization.

  If the result is {:ok, _}, returns it as-is.
  If the result is {:error, _}, sanitizes the error message.

  ## Parameters

  * `result` - The result tuple to format

  ## Returns

  Formatted result tuple

  ## Examples

      iex> format_result({:ok, %{text: "Hello"}})
      {:ok, %{text: "Hello"}}

      iex> format_result({:error, %RuntimeError{message: "Internal"}})
      {:error, "An error occurred"}
  """
  def format_result({:ok, _value} = ok_result), do: ok_result

  def format_result({:error, error}) do
    {:error, sanitize_error(error)}
  end

  @doc """
  Builds canonical AI telemetry metadata for direct LLM actions.
  """
  def telemetry_metadata(context, operation, extra \\ %{})
      when is_map(context) and is_atom(operation) and is_map(extra) do
    %{
      agent_id: context[:agent_id],
      request_id: context[:request_id],
      run_id: context[:run_id] || context[:request_id],
      iteration: context[:iteration],
      llm_call_id: nil,
      tool_call_id: nil,
      tool_name: nil,
      model: context[:model] || context[:default_model],
      origin: :action,
      operation: operation,
      strategy: context[:strategy],
      termination_reason: nil,
      error_type: nil
    }
    |> Map.merge(extra)
  end

  @doc """
  Classifies action-layer LLM errors into canonical telemetry error types.
  """
  def telemetry_error_type(%{type: type}) when is_atom(type), do: type
  def telemetry_error_type(%{code: type}) when is_atom(type), do: type
  def telemetry_error_type(:timeout), do: :timeout
  def telemetry_error_type(_), do: :llm_error

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, value) when is_map(value) and map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_request_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_request_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_request_attrs(_), do: %{}

  defp normalize_optional_map(nil), do: %{}
  defp normalize_optional_map(map) when is_map(map), do: map
  defp normalize_optional_map(map) when is_list(map), do: Map.new(map)
  defp normalize_optional_map(_), do: %{}

  defp merge_optional_maps(left, right), do: Map.merge(left, right)

  defp normalize_backend_metadata(nil), do: %{}
  defp normalize_backend_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_backend_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_backend_metadata(_), do: %{}
end
