defmodule Jido.AI.Provider.Base do
  @moduledoc """
  Base behaviour and default implementation for AI provider modules.

  This module provides a simple, focused API for text generation using AI providers,
  similar to the Vercel AI SDK's `generateText` function.

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

  """

  alias Jido.AI.Error.{API, Invalid}
  alias Jido.AI.{Error, Model, Provider}

  @doc "Returns provider information"
  @callback provider_info() :: Provider.t()

  @doc "Returns the API URL for this provider"
  @callback api_url() :: String.t()

  @doc "Generates text from a Model and prompt"
  @callback generate_text(Model.t(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, Error.t()}

  @doc "Streams text from a Model and prompt, returning an Elixir Stream"
  @callback stream_text(Model.t(), String.t(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Jido.AI.Provider.Base

      import Jido.AI.Provider.Base,
        only: [
          merge_model_options: 3,
          build_chat_completion_body: 3,
          do_http_request: 3,
          # Extract required options
          do_stream_request: 3,
          extract_text_response: 1
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

      # Provide default implementation
      @impl true
      def generate_text(%Model{} = model, prompt, opts \\ []) do
        Jido.AI.Provider.Base.default_generate_text(__MODULE__, model, prompt, opts)
      end

      @impl true
      def stream_text(%Model{} = model, prompt, opts \\ []) do
        Jido.AI.Provider.Base.default_stream_text(__MODULE__, model, prompt, opts)
      end

      # Make callbacks overridable
      defoverridable generate_text: 3, stream_text: 3
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
  @spec default_generate_text(module(), Model.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def default_generate_text(provider_module, %Model{} = model, prompt, opts \\ []) do
    with {:ok, _} <- validate_prompt(prompt),
         {:ok, response} <-
           do_http_request(
             provider_module,
             build_chat_completion_body(
               model,
               prompt,
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
  @spec default_stream_text(module(), Model.t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
  def default_stream_text(provider_module, %Model{} = model, prompt, opts \\ []) do
    with {:ok, _} <- validate_prompt(prompt) do
      merged_opts =
        merge_model_options(provider_module, model, opts)
        |> Keyword.put(:stream, true)

      request_body = build_chat_completion_body(model, prompt, merged_opts)

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
  Builds OpenAI-style chat completion request body.
  """
  @spec build_chat_completion_body(Model.t(), String.t(), keyword()) :: map()
  def build_chat_completion_body(%Model{} = model, prompt, opts) do
    # Convert prompt to messages format
    messages = [%{role: "user", content: prompt}]

    opts
    |> Keyword.put(:messages, messages)
    |> Keyword.put(:model, model.model)
    |> Keyword.take(@chat_completion_opts ++ [:stream])
    |> Map.new()
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
        {:error, reason} -> {:error, API.Request.exception(reason: inspect(reason))}
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
    {:error, API.Request.exception(reason: "HTTP #{status}: #{inspect(body)}")}
  end

  def extract_text_response(response) do
    {:error, API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  defp validate_prompt(prompt) when is_binary(prompt) and prompt != "", do: {:ok, prompt}
  defp validate_prompt(_), do: {:error, Invalid.Parameter.exception(parameter: "prompt")}

  defp get_required_opt(opts, key) do
    case opts[key] do
      nil -> {:error, Invalid.Parameter.exception(parameter: Atom.to_string(key))}
      value -> {:ok, value}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

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
end
