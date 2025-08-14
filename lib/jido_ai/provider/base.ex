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

        # Override default generate_text if needed
        @impl true
        def generate_text(opts) do
          # Custom text generation logic
        end
      end

  ## Callbacks

  * `provider_info/0` - Returns provider metadata (required)
  * `generate_text/1` - Generates text from a prompt (default implementation provided)

  """

  alias Jido.AI.{Provider, Error, Config}

  @doc "Returns provider information"
  @callback provider_info() :: Provider.t()

  @doc "Returns the API URL for this provider"
  @callback api_url() :: String.t()

  @doc "Generates text from a string prompt"
  @callback generate_text(String.t(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, Error.t()}

  @doc "Streams text from a string prompt, returning an Elixir Stream"
  @callback stream_text(String.t(), String.t(), keyword()) ::
              {:ok, Stream.t()} | {:error, Error.t()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Logger
      alias Jido.AI.Provider

      # Extract required options
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
              |> Enum.map(fn model -> {model["id"], model} end)
              |> Map.new()

            {provider_data, models}

          {:error, reason} ->
            Logger.warning("Failed to load provider JSON #{json_path}: #{inspect(reason)}")
            {%{}, %{}}
        end

      # Extract provider metadata with option overrides
      id_atom =
        String.to_atom(
          opts[:id] || provider_meta["id"] || raise(ArgumentError, "provider id not found")
        )

      name = opts[:name] || provider_meta["name"] || Atom.to_string(id_atom) |> Macro.camelize()
      env_vars = opts[:env] || provider_meta["env"] || []
      env_atoms = env_vars |> Enum.map(&String.to_atom/1)

      # Embed provider info and base URL as module attributes
      @provider_info %Provider{
        id: id_atom,
        name: name,
        doc: "",
        env: env_atoms,
        models: models_map
      }
      @base_url base_url

      @behaviour Jido.AI.Provider.Base

      # Import helper functions
      import Jido.AI.Provider.Base,
        only: [
          generate_text_request: 1,
          stream_text_request: 1,
          extract_text_response: 1
        ]

      # Implement callbacks using compile-time data
      @impl true
      def provider_info, do: @provider_info

      @impl true
      def api_url, do: @base_url

      # Provide default implementation
      @impl true
      def generate_text(model, prompt, opts \\ []) do
        Jido.AI.Provider.Base.default_generate_text(__MODULE__, model, prompt, opts)
      end

      @impl true
      def stream_text(model, prompt, opts \\ []) do
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
  Default implementation for generating text.
  """
  def default_generate_text(provider_module, model, prompt, opts \\ []) do
    provider_info = provider_module.provider_info()
    api_url = provider_module.api_url()

    # Build request options
    request_opts =
      opts
      |> Keyword.put(:prompt, prompt)
      |> Keyword.put(:model, model)
      |> Keyword.put(:url, api_url <> "/chat/completions")
      |> put_api_key_from_env(provider_info)

    generate_text_request(request_opts)
  end

  @doc """
  Default implementation for streaming text.
  """
  def default_stream_text(provider_module, model, prompt, opts \\ []) do
    provider_info = provider_module.provider_info()
    api_url = provider_module.api_url()

    # Build request options
    request_opts =
      opts
      |> Keyword.put(:prompt, prompt)
      |> Keyword.put(:model, model)
      |> Keyword.put(:url, api_url <> "/chat/completions")
      |> put_api_key_from_env(provider_info)

    stream_text_request(request_opts)
  end

  @doc """
  Generates a text completion response from the given options.

  ## Options

    * `:prompt` - Text prompt string (required)
    * `:model` - Model identifier (required)
    * `:api_key` - API key for authentication (required)
    * `:url` - API endpoint URL (required)

    * Other options from OpenAI chat completion API

  ## Examples

      iex> Jido.AI.Provider.Base.generate_text_request(
      ...>   prompt: "Hello, how are you?",
      ...>   model: "gpt-4",
      ...>   api_key: "[REDACTED:api-key]",
      ...>   url: "https://api.openai.com/v1/chat/completions"
      ...> )
      {:ok, "I'm doing well, thank you for asking!"}

  """
  @spec generate_text_request(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def generate_text_request(opts \\ []) do
    with {:ok, api_key} <- get_required_opt(opts, :api_key),
         {:ok, url} <- get_required_opt(opts, :url),
         {:ok, _model} <- get_required_opt(opts, :model),
         {:ok, prompt} <- get_required_opt(opts, :prompt) do
      # Convert prompt to messages format
      messages = [%{role: "user", content: prompt}]

      request_opts =
        opts
        |> Keyword.put(:messages, messages)
        |> Keyword.take(@chat_completion_opts)

      http_client = Config.get_http_client()
      
      case http_client.post(url,
             json: Map.new(request_opts),
             auth: {:bearer, api_key},
             receive_timeout: 60_000,
             pool_timeout: 30_000
           ) do
        {:ok, response} -> extract_text_response(response)
        {:error, reason} -> {:error, Error.API.Request.exception(reason: inspect(reason))}
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Streams text completion responses from the given options.

  ## Options

    * `:prompt` - Text prompt string (required)
    * `:model` - Model identifier (required)
    * `:api_key` - API key for authentication (required)
    * `:url` - API endpoint URL (required)

    * Other options from OpenAI chat completion API

  ## Examples

      iex> stream = Jido.AI.Provider.Base.stream_text_request(
      ...>   prompt: "Hello, how are you?",
      ...>   model: "gpt-4",
      ...>   api_key: "[REDACTED:api-key]",
      ...>   url: "https://api.openai.com/v1/chat/completions"
      ...> )
      iex> {:ok, stream} = stream
      iex> stream |> Enum.take(3)
      ["Hello", " there", "!"]

  """
  @spec stream_text_request(keyword()) :: {:ok, Stream.t()} | {:error, Error.t()}
  def stream_text_request(opts \\ []) do
    with {:ok, api_key} <- get_required_opt(opts, :api_key),
         {:ok, url} <- get_required_opt(opts, :url),
         {:ok, _model} <- get_required_opt(opts, :model),
         {:ok, prompt} <- get_required_opt(opts, :prompt) do
      # Convert prompt to messages format
      messages = [%{role: "user", content: prompt}]

      request_opts =
        opts
        |> Keyword.put(:messages, messages)
        |> Keyword.put(:stream, true)
        |> Keyword.take(@chat_completion_opts ++ [:stream])

      stream =
        Stream.resource(
          fn ->
            pid = self()

            Task.async(fn ->
              http_client = Config.get_http_client()
              
              try do
                http_client.post(url,
                  json: Map.new(request_opts),
                  auth: {:bearer, api_key},
                  receive_timeout: 60_000,
                  pool_timeout: 30_000,
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
            receive do
              :done ->
                {:halt, task}

              {:error, error} ->
                throw({:error, Error.API.Request.exception(reason: inspect(error))})

              {:events, events} ->
                {parse_stream_events(events), task}
            after
              15_000 -> {:halt, task}
            end
          end,
          fn task ->
            Task.await(task, 15_000)
          end
        )

      {:ok, stream}
    else
      {:error, _} = error -> error
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
        {:error, Error.API.Request.exception(reason: "Invalid response format")}
    end
  end

  def extract_text_response(%{status: status, body: body}) when status >= 400 do
    {:error, Error.API.Request.exception(reason: "HTTP #{status}: #{inspect(body)}")}
  end

  def extract_text_response(response) do
    {:error, Error.API.Request.exception(reason: "Unexpected response: #{inspect(response)}")}
  end

  defp get_required_opt(opts, key) do
    case opts[key] do
      nil -> {:error, Error.Invalid.Parameter.exception(parameter: Atom.to_string(key))}
      value -> {:ok, value}
    end
  end

  defp put_api_key_from_env(opts, provider_info) do
    case provider_info.env do
      [env_var | _] when is_atom(env_var) ->
        # Convert env var to atom format expected by keyring
        keyring_key =
          env_var
          |> Atom.to_string()
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9_]/, "_")
          |> String.to_atom()

        case Jido.AI.Keyring.get(keyring_key) do
          nil -> opts
          api_key -> Keyword.put(opts, :api_key, api_key)
        end

      _ ->
        opts
    end
  end

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
