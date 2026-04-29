defmodule Jido.AI.Directive.LLMEmbed do
  # covers: jido_ai.runtime_contracts.directive_signal_envelopes jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Directive asking the runtime to generate embeddings.

  The runtime executes this through the configured backend and sends the result
  as an `ai.embed.result` signal.

  Supports both single text and batch embedding (list of texts).
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique call ID for correlation"),
              model: Zoi.string(description: "Embedding model spec, e.g. 'openai:text-embedding-3-small'"),
              backend:
                Zoi.atom(description: "Optional backend override (:req_llm | :harness)")
                |> Zoi.optional(),
              texts: Zoi.any(description: "Text string or list of text strings to embed"),
              dimensions:
                Zoi.integer(description: "Number of dimensions for embedding vector")
                |> Zoi.optional(),
              timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
              workspace:
                Zoi.map(description: "Backend-neutral workspace context such as cwd or attachments")
                |> Zoi.default(%{}),
              backend_metadata:
                Zoi.map(description: "Backend-specific additive metadata such as Harness provider selection")
                |> Zoi.default(%{}),
              metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Create a new LLMEmbed directive."
  def new!(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid LLMEmbed: #{inspect(errors)}"
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMEmbed do
  @moduledoc """
  Spawns an async task to generate embeddings and sends the result back to the
  agent.

  Supports both single text and batch embedding (list of texts).
  """

  alias Jido.AI.{Backends, Signal}
  alias Jido.AI.Directive.Helpers

  def exec(directive, _input_signal, state) do
    %{id: call_id} = directive

    request = Helpers.build_embedding_request(directive)

    agent_pid = self()
    task_supervisor = Helpers.get_task_supervisor(state)

    case Task.Supervisor.start_child(task_supervisor, fn ->
           result =
             try do
               generate_embeddings(request)
             rescue
               e ->
                 {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
             catch
               kind, reason ->
                 {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
             end

           signal = Signal.EmbedResult.new!(%{call_id: call_id, result: result})
           Jido.AgentServer.cast(agent_pid, signal)
         end) do
      {:ok, _pid} ->
        {:async, nil, state}

      {:error, reason} ->
        signal =
          Signal.EmbedResult.new!(%{
            call_id: call_id,
            result: {:error, %{type: :supervisor, reason: inspect(reason), error_type: :unknown}}
          })

        Jido.AgentServer.cast(agent_pid, signal)
        {:ok, state}
    end
  end

  defp generate_embeddings(request) do
    case Backends.generate(request) do
      {:ok, result} ->
        embeddings = result.embeddings || []
        {:ok, %{embeddings: embeddings, count: count_embeddings(embeddings)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_embeddings(embeddings) when is_list(embeddings), do: length(embeddings)
end
