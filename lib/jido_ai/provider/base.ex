defmodule Jido.AI.Provider.Base do
  @moduledoc """
  Base behaviour and default implementation for AI provider modules.

  This module provides a simple, focused API for text generation using AI providers,
  inspired by the Vercel AI SDK's `generateText` function.

  ## Usage

  To create a new provider, use this module and implement the required callbacks:

      defmodule MyProvider do
        use Jido.AI.Provider.Base

        @impl true
        def provider_info do
          %Jido.AI.Provider{
            id: "myprovider",
            name: "My Provider",
            doc: "Custom provider implementation",
            env: ["MY_PROVIDER_API_KEY"],
            models: %{}
          }
        end

        # Override default generate_text if needed for specific models
        @impl true
        def generate_text(%Model{model: "special-model"} = model, prompt, opts) do
          # Custom implementation for special-model
        end

        # All other models use default implementation
        defoverridable generate_text: 3, stream_text: 3
      end

  ## Callbacks

  * `provider_info/0` - Returns provider metadata (required)
  * `generate_text/3` - Generates text from a Model and prompt (default implementation provided)
  * `stream_text/3` - Streams text from a Model and prompt (default implementation provided)
  * `generate_object/4` - Generates structured data from a Model, prompt, and schema (default implementation provided)
  * `stream_object/4` - Streams structured data from a Model, prompt, and schema (default implementation provided)

  """

  alias Jido.AI.Error.SchemaValidation
  alias Jido.AI.Error.{API, Invalid}
  alias Jido.AI.{ContentPart, Error, Message, Model, ObjectSchema, Provider}

  @doc "Returns provider information"
  @callback provider_info() :: Provider.t()

  @doc "Returns the API URL for this provider"
  @callback api_url() :: String.t()

  @doc "Returns true if provider supports native JSON response formatting"
  @callback supports_json_mode?() :: boolean()

  @doc "Generates text from a Model and prompt"
  @callback generate_text(Model.t(), String.t() | [Message.t()], keyword()) ::
              {:ok, String.t()} | {:error, Error.t()}

  @doc "Streams text from a Model and prompt, returning an Elixir Stream"
  @callback stream_text(Model.t(), String.t() | [Message.t()], keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  @doc "Generates structured data from a Model, prompt, and schema"
  @callback generate_object(Model.t(), String.t() | [Message.t()], map(), keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @doc "Streams structured data from a Model, prompt, and schema, returning an Elixir Stream"
  @callback stream_object(Model.t(), String.t() | [Message.t()], map(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Jido.AI.Provider.Base

      import Jido.AI.Provider.Base,
        only: [
          merge_model_options: 3,
          build_chat_completion_body: 4,
          do_http_request: 3,
          # Extract required options
          do_stream_request: 3,
          extract_text_response: 1,
          extract_object_response: 1
        ]

      alias Jido.AI.{Model, Provider}

      require Logger

      json_filename =
        opts[:json] || raise ArgumentError, "expected :json option with JSON filename"

      base_url = opts[:base_url] || raise ArgumentError, "expected :base_url option"

      # Build full JSON path
      json_path = Path.join(:code.priv_dir(:jido_ai), "models_dev/#{json_filename}")

      # Mark file as external resource for recompilation
      @external_resource json_path

      # Load JSON data at compile time
      {provider_meta, models_map} =
        case File.read(json_path) do
          {:ok, json_content} ->
            data = Jason.decode!(json_content)
            provider_data = data["provider"] || %{}

            models =
              data
              |> Map.get("models", [])
              |> Map.new(fn model -> {model["id"], model} end)

            {provider_data, models}

          {:error, reason} ->
            Logger.warning("Failed to load provider JSON #{json_path}: #{inspect(reason)}")
            {%{}, %{}}
        end

      # Extract provider metadata with option overrides
      id_atom =
        String.to_atom(opts[:id] || provider_meta["id"] || raise(ArgumentError, "provider id not found"))

      name = opts[:name] || provider_meta["name"] || Atom.to_string(id_atom) |> Macro.camelize()
      env_vars = opts[:env] || provider_meta["env"] || []
      env_atoms = env_vars |> Enum.map(&String.to_atom/1)

      # Embed provider info and base URL as module attributes
      @provider_info %Provider{
        id: id_atom,
        name: name,
        base_url: base_url,
        doc: "",
        env: env_atoms,
        models: models_map
      }
      @base_url base_url

      # Import helper functions

      # Implement callbacks using compile-time data
      @impl true
      def provider_info, do: @provider_info

      @impl true
      def api_url, do: @base_url

      # Default to not supporting JSON mode - providers can override
      @impl true
      def supports_json_mode?, do: false

      # Provide default implementation
      @impl true
      def generate_text(%Model{} = model, prompt, opts \\ []) do
        Jido.AI.Provider.Base.default_generate_text(__MODULE__, model, prompt, opts)
      end

      @impl true
      def stream_text(%Model{} = model, prompt, opts \\ []) do
        Jido.AI.Provider.Base.default_stream_text(__MODULE__, model, prompt, opts)
      end

      @impl true
      def generate_object(%Model{} = model, prompt, schema, opts \\ []) do
        Jido.AI.Provider.Base.default_generate_object(__MODULE__, model, prompt, schema, opts)
      end

      @impl true
      def stream_object(%Model{} = model, prompt, schema, opts \\ []) do
        Jido.AI.Provider.Base.default_stream_object(__MODULE__, model, prompt, schema, opts)
      end

      # Make callbacks overridable
      defoverridable generate_text: 3,
                     stream_text: 3,
                     generate_object: 4,
                     stream_object: 4,
                     supports_json_mode?: 0
    end
  end

  # Supported options for chat completion requests
  @chat_completion_opts ~w(
    model
    messages
    frequency_penalty
    max_completion_tokens
    max_tokens
    n
    presence_penalty
    response_format
    seed
    stop
    temperature
    top_p
    user
  )a

  @doc """
  Default implementation for generating text using OpenAI-style chat completions.
  """
  @spec default_generate_text(module(), Model.t(), String.t() | [Message.t()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def default_generate_text(provider_module, %Model{} = model, prompt, opts \\ []) do
    system_prompt = Keyword.get(opts, :system_prompt)

    with {:ok, _} <- validate_prompt(prompt),
         {:ok, response} <-
           do_http_request(
             provider_module,
             build_chat_completion_body(
               model,
               prompt,
               system_prompt,
               merge_model_options(provider_module, model, opts)
             ),
             merge_model_options(provider_module, model, opts)
           ) do
      extract_text_response(response)
    end
  end

  @doc """
  Default implementation for streaming text using OpenAI-style chat completions.
  """
  @spec default_stream_text(module(), Model.t(), String.t() | [Message.t()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def default_stream_text(provider_module, %Model{} = model, prompt, opts \\ []) do
    system_prompt = Keyword.get(opts, :system_prompt)

    with {:ok, _} <- validate_prompt(prompt) do
      merged_opts =
        merge_model_options(provider_module, model, opts)
        |> Keyword.put(:stream, true)

      request_body = build_chat_completion_body(model, prompt, system_prompt, merged_opts)

      do_stream_request(provider_module, request_body, merged_opts)
    end
  end

  @doc """
  Default implementation for generating structured data using OpenAI-style chat completions.

  Supports retry logic for validation failures via `max_retries` option.
  """
  @spec default_generate_object(module(), Model.t(), String.t() | [Message.t()], map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def default_generate_object(provider_module, %Model{} = model, prompt, schema, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, model.max_retries || 3)
    do_generate_object_with_retry(provider_module, model, prompt, schema, opts, max_retries, 0)
  end

  defp do_generate_object_with_retry(provider_module, model, prompt, schema, opts, max_retries, attempt) do
    system_prompt = build_schema_system_prompt(schema, Keyword.get(opts, :system_prompt))

    with {:ok, _} <- validate_prompt(prompt),
         {:ok, _} <- validate_schema(schema) do
      merged_opts =
        merge_model_options(provider_module, model, opts)
        |> maybe_add_json_mode(provider_module)

      with {:ok, response} <-
             do_http_request(
               provider_module,
               build_chat_completion_body(model, prompt, system_prompt, merged_opts),
               merged_opts
             ),
           {:ok, object} <- extract_object_response(response),
           {:ok, schema_struct} <- ObjectSchema.new(schema),
           {:ok, validated_object} <- ObjectSchema.validate(schema_struct, object) do
        {:ok, validated_object}
      else
        {:error, %SchemaValidation{} = error} when attempt < max_retries ->
          # Build retry prompt with validation error feedback
          retry_prompt = build_retry_prompt(prompt, schema, error)
          do_generate_object_with_retry(provider_module, model, retry_prompt, schema, opts, max_retries, attempt + 1)

        {:error, _} = error ->
          error
      end
    end
  end

  @doc false
  def build_retry_prompt(original_prompt, _schema, %SchemaValidation{validation_errors: errors}) do
    error_feedback = format_validation_errors_for_retry(errors)

    """
    #{original_prompt}

    VALIDATION ERROR: The previous response failed schema validation with the following errors:
    #{error_feedback}

    Please correct these issues and respond with valid JSON that strictly follows the required schema.
    """
  end

  defp format_validation_errors_for_retry(errors) when is_list(errors) do
    errors
    |> Enum.map_join("\n", &format_single_validation_error/1)
  end

  defp format_validation_errors_for_retry(_), do: "Invalid data format"

  defp format_single_validation_error(%{field: field, message: message}) do
    "- #{field}: #{message}"
  end

  defp format_single_validation_error(%{path: path, message: message}) when is_list(path) do
    path_str = Enum.join(path, ".")
    "- #{path_str}: #{message}"
  end

  defp format_single_validation_error(error) when is_binary(error) do
    "- #{error}"
  end

  defp format_single_validation_error(error) do
    "- #{inspect(error)}"
  end

  @doc """
  Default implementation for streaming structured data using OpenAI-style chat completions.

  Returns a stream of text content chunks, similar to stream_text but for structured output.
  Final validation should be handled by the consumer.
  """
  @spec default_stream_object(module(), Model.t(), String.t() | [Message.t()], map() | keyword(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def default_stream_object(provider_module, %Model{} = model, prompt, schema, opts \\ []) do
    system_prompt = build_schema_system_prompt(schema, Keyword.get(opts, :system_prompt))

    with {:ok, _} <- validate_prompt(prompt),
         {:ok, _} <- validate_schema(schema) do
      merged_opts =
        merge_model_options(provider_module, model, opts)
        |> Keyword.put(:stream, true)
        |> maybe_add_json_mode(provider_module)

      request_body = build_chat_completion_body(model, prompt, system_prompt, merged_opts)

      # Return stream of text chunks for structured output - validation handled by consumer
      do_stream_request(provider_module, request_body, merged_opts)
    end
  end

  @doc """
  Merges Model configuration with request options.
  Model options are used as defaults, opts take precedence.
  """
  @spec merge_model_options(module(), Model.t(), keyword()) :: keyword()
  def merge_model_options(provider_module, %Model{} = model, opts) do
    # Get API key from model's provider configuration or opts
    api_key =
      Keyword.get(opts, :api_key) ||
        Jido.AI.config([model.provider, :api_key])

    # Get base URL from provider module
    base_url = provider_module.api_url()

    model_opts =
      []
      |> maybe_put(:temperature, model.temperature)
      |> maybe_put(:max_tokens, model.max_tokens)
      |> maybe_put(:max_retries, model.max_retries)
      |> maybe_put(:api_key, api_key)
      |> maybe_put(:url, base_url <> "/chat/completions")

    # Provided opts take precedence over model defaults
    Keyword.merge(model_opts, opts)
  end

  @doc """
  Merges provider-specific options from multiple levels with correct precedence.

  Precedence (highest to lowest):
  1. Content-part level metadata
  2. Message level metadata
  3. Function level opts parameter
  4. Model defaults (handled in merge_model_options)

  ## Parameters

    * `model` - The Model struct (for provider context)
    * `prompt` - String or list of Message structs
    * `function_opts` - Options passed to generate_text/stream_text functions
    * `provider_opts` - Existing provider options from function level

  ## Examples

      iex> merge_provider_options(model, "hello", [], %{})
      %{}

      iex> messages = [%Message{content: "hi", metadata: %{provider_options: %{openai: %{temp: 0.5}}}}]
      iex> merge_provider_options(model, messages, [], %{})
      %{openai: %{temp: 0.5}}

  """
  @spec merge_provider_options(Model.t(), String.t() | [Message.t()], keyword(), map()) :: map()
  def merge_provider_options(%Model{provider: _provider}, prompt, function_opts, base_provider_opts) do
    # Start with base provider options (from function level or model)
    acc = base_provider_opts

    # Extract provider options from function level opts
    function_provider_opts = Keyword.get(function_opts, :provider_options, %{})
    acc = deep_merge_provider_options(acc, function_provider_opts)

    # Extract provider options from messages (if prompt is message list)
    case prompt do
      messages when is_list(messages) ->
        messages
        |> Enum.reduce(acc, fn message, acc_opts ->
          message_opts = Message.provider_options(message)
          acc_opts = deep_merge_provider_options(acc_opts, message_opts)

          # Extract content part options if content is a list
          case message.content do
            content_parts when is_list(content_parts) ->
              Enum.reduce(content_parts, acc_opts, fn part, part_acc_opts ->
                part_opts = ContentPart.provider_options(part)
                deep_merge_provider_options(part_acc_opts, part_opts)
              end)

            _ ->
              acc_opts
          end
        end)

      _ ->
        acc
    end
  end

  # Deep merge provider options with proper precedence
  defp deep_merge_provider_options(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, base_val, override_val ->
      case {base_val, override_val} do
        {base_map, override_map} when is_map(base_map) and is_map(override_map) ->
          deep_merge_provider_options(base_map, override_map)

        {_, override_val} ->
          override_val
      end
    end)
  end

  defp deep_merge_provider_options(_base, override), do: override

  @doc """
  Builds OpenAI-style chat completion request body with provider options support.
  """
  @spec build_chat_completion_body(
          Model.t(),
          String.t() | [Message.t()],
          String.t() | nil,
          keyword()
        ) :: map()
  def build_chat_completion_body(%Model{} = model, prompt, system_prompt, opts) do
    # Convert prompt to messages format
    messages = encode_messages(prompt)

    # Prepend system message if system_prompt is provided
    final_messages =
      if system_prompt do
        [%{role: "system", content: system_prompt} | messages]
      else
        messages
      end

    # Get provider-specific options for this provider
    provider_options = merge_provider_options(model, prompt, opts, %{})
    provider_opts_for_model = Map.get(provider_options, model.provider, %{})

    base_body =
      opts
      |> Keyword.put(:messages, final_messages)
      |> Keyword.put(:model, model.model)
      |> Keyword.take(@chat_completion_opts ++ [:stream])
      |> Map.new()

    # Merge provider-specific options into request body
    Map.merge(base_body, provider_opts_for_model)
  end

  @doc """
  Performs HTTP request for text generation.
  """
  @spec do_http_request(module(), map(), keyword()) :: {:ok, struct()} | {:error, Error.t()}
  def do_http_request(_provider_module, request_body, opts) do
    with {:ok, api_key} <- get_required_opt(opts, :api_key),
         {:ok, url} <- get_required_opt(opts, :url) do
      http_client = Jido.AI.config([:http_client], Req)
      http_options = Jido.AI.config([:http_options], [])

      recv_to = Keyword.get(opts, :receive_timeout, Jido.AI.config([:receive_timeout], 60_000))
      pool_to = Keyword.get(opts, :pool_timeout, Jido.AI.config([:pool_timeout], 30_000))

      client = http_client.new(http_options)

      case http_client.post(client,
             url: url,
             json: request_body,
             auth: {:bearer, api_key},
             receive_timeout: recv_to,
             pool_timeout: pool_to
           ) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, build_enhanced_api_error(reason, request_body)}
      end
    end
  end

  @doc """
  Performs streaming HTTP request for text generation.
  """
  @spec do_stream_request(module(), map(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def do_stream_request(_provider_module, request_body, opts) do
    with {:ok, api_key} <- get_required_opt(opts, :api_key),
         {:ok, url} <- get_required_opt(opts, :url) do
      stream =
        Stream.resource(
          fn ->
            pid = self()

            Task.async(fn ->
              http_client = Jido.AI.config([:http_client], Req)

              recv_to =
                Keyword.get(opts, :receive_timeout, Jido.AI.config([:receive_timeout], 60_000))

              pool_to = Keyword.get(opts, :pool_timeout, Jido.AI.config([:pool_timeout], 30_000))

              try do
                http_client.post(url,
                  json: request_body,
                  auth: {:bearer, api_key},
                  receive_timeout: recv_to,
                  pool_timeout: pool_to,
                  into: fn {:data, data}, {req, resp} ->
                    buffer = Req.Request.get_private(req, :sse_buffer, "")
                    {events, new_buffer} = ServerSentEvents.parse(buffer <> data)

                    if events != [] do
                      send(pid, {:events, events})
                    end

                    {:cont, {Req.Request.put_private(req, :sse_buffer, new_buffer), resp}}
                  end
                )
              rescue
                e -> send(pid, {:error, e})
              after
                send(pid, :done)
              end
            end)
          end,
          fn task ->
            inactivity_to =
              Keyword.get(
                opts,
                :stream_inactivity_timeout,
                Jido.AI.config([:stream_inactivity_timeout], 15_000)
              )

            receive do
              :done ->
                {:halt, task}

              {:error, error} ->
                throw({:error, API.Request.exception(reason: inspect(error))})

              {:events, events} ->
                {parse_stream_events(events), task}
            after
              inactivity_to -> {:halt, task}
            end
          end,
          fn task ->
            Task.await(task, 15_000)
          end
        )

      {:ok, stream}
    end
  end

  @doc """
  Extracts the text content from a chat completion response.

  ## Examples

      iex> response = %Req.Response{
      ...>   status: 200,
      ...>   body: %{
      ...>     "choices" => [
      ...>       %{"message" => %{"content" => "Hello there!"}}
      ...>     ]
      ...>   }
      ...> }
      iex> Jido.AI.Provider.Base.extract_text_response(response)
      {:ok, "Hello there!"}

  """
  @spec extract_text_response(struct()) :: {:ok, String.t()} | {:error, Error.t()}
  def extract_text_response(%{status: 200, body: body}) do
    case body do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        {:ok, content}

      _ ->
        {:error, API.Request.exception(reason: "Invalid response format")}
    end
  end

  def extract_text_response(%{status: status, body: body}) when status >= 400 do
    {:error,
     API.Request.exception(
       reason: format_http_error(status, body),
       status: status,
       response_body: body
     )}
  end

  def extract_text_response(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  @doc """
  Extracts structured data from a chat completion response.

  ## Examples

      iex> response = %Req.Response{
      ...>   status: 200,
      ...>   body: %{
      ...>     "choices" => [
      ...>       %{"message" => %{"content" => "{\"name\": \"John\", \"age\": 30}"}}
      ...>     ]
      ...>   }
      ...> }
      iex> Jido.AI.Provider.Base.extract_object_response(response)
      {:ok, %{"name" => "John", "age" => 30}}

  """
  @spec extract_object_response(struct()) :: {:ok, map()} | {:error, Error.t()}
  def extract_object_response(%{status: 200, body: body}) do
    case body do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        parse_json_response(content)

      _ ->
        {:error, API.Request.exception(reason: "Invalid response format")}
    end
  end

  def extract_object_response(%{status: status, body: body}) when status >= 400 do
    {:error,
     API.Request.exception(
       reason: format_http_error(status, body),
       status: status,
       response_body: body
     )}
  end

  def extract_object_response(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  @doc """
  Encodes prompts to OpenAI-style messages format.

  Handles both string prompts (converted to user message) and Message lists
  (converted to OpenAI format).
  """
  @spec encode_messages(String.t() | [Message.t()]) :: [map()]
  def encode_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  def encode_messages(messages) when is_list(messages) do
    Enum.map(messages, &encode_message/1)
  end

  @doc """
  Converts a Message struct to OpenAI API format.
  """
  @spec encode_message(Message.t()) :: map()
  def encode_message(%Message{role: role, content: content} = message) do
    base_message = %{
      "role" => Atom.to_string(role),
      "content" => encode_content(content)
    }

    base_message
    |> maybe_put_string("name", message.name)
    |> maybe_put_string("tool_call_id", message.tool_call_id)
    |> maybe_put_list("tool_calls", message.tool_calls)
  end

  defp encode_content(content) when is_binary(content), do: content

  defp encode_content(content_parts) when is_list(content_parts) do
    # Convert list of ContentPart structs to OpenAI format
    Enum.map(content_parts, &ContentPart.to_map/1)
  end

  defp validate_prompt(prompt) when is_binary(prompt) and prompt != "", do: {:ok, prompt}

  defp validate_prompt(messages) when is_list(messages) do
    cond do
      Enum.empty?(messages) ->
        {:error, Invalid.Parameter.exception(parameter: "prompt")}

      Enum.all?(messages, &Message.valid?/1) ->
        {:ok, messages}

      true ->
        {:error, Invalid.Parameter.exception(parameter: "prompt")}
    end
  end

  defp validate_prompt(_), do: {:error, Invalid.Parameter.exception(parameter: "prompt")}

  defp get_required_opt(opts, key) do
    case opts[key] do
      nil -> {:error, Invalid.Parameter.exception(parameter: Atom.to_string(key))}
      value -> {:ok, value}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, key, value) when is_binary(value), do: Map.put(map, key, value)

  defp maybe_put_list(map, _key, nil), do: map
  defp maybe_put_list(map, _key, []), do: map
  defp maybe_put_list(map, key, value) when is_list(value), do: Map.put(map, key, value)

  defp parse_stream_events(events) do
    events
    |> Enum.flat_map(fn event ->
      case event do
        %{data: "[DONE]"} ->
          []

        %{data: data} when is_binary(data) ->
          case Jason.decode(data) do
            {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}}
            when is_binary(content) ->
              [content]

            {:ok, _} ->
              []

            {:error, _} ->
              []
          end

        _ ->
          []
      end
    end)
  end

  # Helper functions for structured data generation

  # Builds a system prompt that includes schema guidance for structured output.
  @spec build_schema_system_prompt(map() | keyword(), String.t() | nil) :: String.t()
  @doc false
  def build_schema_system_prompt(schema, existing_system_prompt) do
    # Convert schema to proper format for JSON encoding
    json_schema =
      case schema do
        schema when is_list(schema) ->
          # Convert keyword list to ObjectSchema format for JSON encoding
          case ObjectSchema.new(properties: schema) do
            {:ok, object_schema} -> object_schema
            {:error, _} -> %{properties: Map.new(schema)}
          end

        schema when is_map(schema) ->
          schema
      end

    schema_prompt = """
    You must respond with valid JSON that conforms to the following JSON schema:

    #{Jason.encode!(json_schema, pretty: true)}

    Ensure your response is valid JSON and matches the schema exactly.
    """

    case existing_system_prompt do
      nil -> schema_prompt
      existing -> existing <> "\n\n" <> schema_prompt
    end
  end

  # Validates that the schema is a valid structure (map or keyword list).
  @spec validate_schema(map() | keyword()) :: {:ok, map() | keyword()} | {:error, Error.t()}
  defp validate_schema(schema) when (is_map(schema) and schema != %{}) or (is_list(schema) and schema != []) do
    {:ok, schema}
  end

  defp validate_schema(_) do
    {:error, Invalid.Parameter.exception(parameter: "schema")}
  end

  # Parses JSON content from API response, returning appropriate errors for invalid JSON.
  @spec parse_json_response(String.t()) :: {:ok, map()} | {:error, Error.t()}
  defp parse_json_response(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, _} ->
        {:error, API.Request.exception(reason: "Response is not a JSON object")}

      {:error, reason} ->
        {:error, API.Request.exception(reason: "Invalid JSON: #{inspect(reason)}")}
    end
  end

  # Helper function to conditionally add JSON mode based on provider support
  @spec maybe_add_json_mode(keyword(), module()) :: keyword()
  defp maybe_add_json_mode(opts, provider_module) do
    if provider_module.supports_json_mode?() do
      Keyword.put(opts, :response_format, %{type: "json_object"})
    else
      opts
    end
  end

  # Enhanced error handling with API response details
  defp build_enhanced_api_error(reason, request_body) do
    case reason do
      %Req.Response{status: status, body: body} when status >= 400 ->
        API.Request.exception(
          reason: format_http_error(status, body),
          status: status,
          response_body: body,
          request_body: sanitize_request_body(request_body)
        )

      %{response: %{status: status, body: body}} when status >= 400 ->
        API.Request.exception(
          reason: format_http_error(status, body),
          status: status,
          response_body: body,
          request_body: sanitize_request_body(request_body)
        )

      %{__exception__: true} = exception ->
        API.Request.exception(
          reason: "Network error: #{Exception.message(exception)}",
          cause: exception,
          request_body: sanitize_request_body(request_body)
        )

      other ->
        API.Request.exception(
          reason: "Request failed: #{inspect(other)}",
          cause: other,
          request_body: sanitize_request_body(request_body)
        )
    end
  end

  defp format_http_error(status, body) when is_map(body) do
    case get_in(body, ["error", "message"]) do
      nil ->
        case get_in(body, ["error"]) do
          error_msg when is_binary(error_msg) -> error_msg
          _ -> "HTTP #{status}"
        end

      error_msg when is_binary(error_msg) ->
        error_type = get_in(body, ["error", "type"]) || "unknown"
        "#{error_msg} (#{error_type})"
    end
  end

  defp format_http_error(status, body) when is_binary(body) do
    "HTTP #{status}: #{String.slice(body, 0, 200)}"
  end

  defp format_http_error(status, _), do: "HTTP #{status}"

  defp sanitize_request_body(body) when is_map(body) do
    # Remove sensitive data but keep structure for debugging
    body
    |> Map.delete("api_key")
    |> Map.put("messages", "[REDACTED]")
  end

  defp sanitize_request_body(body), do: body
end
