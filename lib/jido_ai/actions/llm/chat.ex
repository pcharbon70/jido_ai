defmodule Jido.AI.Actions.LLM.Chat do
  @moduledoc """
  A Jido.Action for chat-style LLM interactions with optional system prompts.

  This action uses ReqLLM directly to generate chat-style responses from
  language models. It supports model aliases via `Jido.AI.resolve_model/1` and
  optional system prompts for conversation context.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:fast`, `:capable`) or direct spec (e.g., `"anthropic:claude-haiku-4-5"`)
  * `prompt` (required) - The user prompt to send to the LLM
  * `system_prompt` (optional) - System prompt to guide the LLM's behavior
  * `max_tokens` (optional) - Maximum tokens to generate (default: `1024`)
  * `temperature` (optional) - Sampling temperature 0.0-2.0 (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic chat
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        prompt: "What is Elixir?"
      })

      # With system prompt
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        model: :capable,
        prompt: "Explain GenServers",
        system_prompt: "You are an expert Elixir teacher.",
        temperature: 0.5
      })

      # Direct model spec
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        model: "openai:gpt-4",
        prompt: "Hello!"
      })
  """

  use Jido.Action,
    name: "llm_chat",
    description: "Send a chat message to an LLM and get a response",
    category: "ai",
    tags: ["llm", "chat", "generation"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :fast) or direct model spec string")
          |> Zoi.optional(),
        backend:
          Zoi.any(description: "Optional additive backend selector such as :req_llm or :harness")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The user prompt to send to the LLM"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
        temperature: Zoi.float(description: "Sampling temperature (0.0-2.0)") |> Zoi.default(0.7),
        workspace:
          Zoi.map(description: "Optional backend-neutral workspace context such as cwd or attachments")
          |> Zoi.optional(),
        backend_metadata:
          Zoi.map(description: "Optional backend-specific additive metadata")
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Error.Sanitize
  alias Jido.AI.Observe
  alias ReqLLM.Context

  @doc """
  Executes the chat action.

  ## Returns

  * `{:ok, result}` - Successful response with `text`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        text: "The LLM's response text",
        model: "anthropic:claude-haiku-4-5",
        usage: %{
          input_tokens: 10,
          output_tokens: 25,
          total_tokens: 35
        }
      }
  """
  @impl Jido.Action
  def run(params, context) do
    params = apply_context_defaults(params, context)
    obs_cfg = context[:observability] || %{}
    prompt_length = if is_binary(params[:prompt]), do: String.length(params[:prompt]), else: 0

    base_metadata =
      Helpers.telemetry_metadata(context, :chat, %{
        action: "llm_chat",
        model: params[:model],
        prompt_length: prompt_length
      })

    Observe.emit(obs_cfg, Observe.llm(:start), %{system_time: System.system_time()}, base_metadata)

    start_time = System.monotonic_time()

    with {:ok, validated_params} <- Helpers.validate_and_sanitize_input(params),
         {:ok, req_context} <-
           build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         {:ok, result} <-
           Helpers.generate_backend_result(validated_params, %{
             default_model: :fast,
             operation: :text,
             messages: req_context.messages
           }) do
      duration_native = System.monotonic_time() - start_time

      measurements = %{
        duration: duration_native,
        duration_ms: System.convert_time_unit(duration_native, :native, :millisecond)
      }

      result_metadata =
        base_metadata
        |> Map.merge(%{
          model: result.model,
          usage: result.usage || Helpers.extract_usage(%{})
        })
        |> Observe.sanitize_sensitive()

      Observe.emit(obs_cfg, Observe.llm(:complete), measurements, result_metadata)
      {:ok, format_result(result)}
    else
      {:error, reason} ->
        duration_native = System.monotonic_time() - start_time

        error_metadata =
          base_metadata
          |> Map.merge(%{
            error_type: Helpers.telemetry_error_type(reason),
            error_reason: inspect(reason),
            termination_reason: :error
          })
          |> Observe.sanitize_sensitive()

        Observe.emit(
          obs_cfg,
          Observe.llm(:error),
          %{
            duration: duration_native,
            duration_ms: System.convert_time_unit(duration_native, :native, :millisecond)
          },
          error_metadata
        )

        {:error, sanitize_error_for_user(reason)}
    end
  end

  # Private Functions

  defp sanitize_error_for_user(error) when is_struct(error) do
    Sanitize.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(error) when is_atom(error) do
    Sanitize.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(_error), do: "An error occurred"

  defp build_messages(prompt, nil) do
    Context.normalize(prompt, [])
  end

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Context.normalize(prompt, system_prompt: system_prompt)
  end

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)

    model_default =
      first_present([
        context[:default_model],
        context[:model],
        plugin_default(context, :default_model)
      ])

    system_prompt_default =
      first_present([
        context[:default_system_prompt],
        plugin_default(context, :default_system_prompt),
        plugin_default(context, :system_prompt)
      ])

    max_tokens_default =
      first_present([
        context[:default_max_tokens],
        plugin_default(context, :default_max_tokens)
      ])

    temperature_default =
      first_present([
        context[:default_temperature],
        plugin_default(context, :default_temperature)
      ])

    backend_default =
      first_present([
        context[:backend],
        plugin_default(context, :backend)
      ])

    workspace_default =
      first_present([
        normalize_optional_map(context[:workspace]),
        normalize_optional_map(plugin_default(context, :workspace))
      ])

    backend_metadata_default =
      merge_optional_maps(
        normalize_optional_map(plugin_default(context, :backend_metadata)),
        normalize_optional_map(context[:backend_metadata])
      )

    params
    |> put_default_param(:model, model_default, provided)
    |> put_default_param(:system_prompt, system_prompt_default, provided)
    |> put_default_param(:max_tokens, max_tokens_default, provided)
    |> put_default_param(:temperature, temperature_default, provided)
    |> put_default_param(:backend, backend_default, provided)
    |> merge_map_default(:workspace, workspace_default, provided)
    |> merge_map_default(:backend_metadata, backend_metadata_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp merge_map_default(params, _key, defaults, _provided) when defaults == %{}, do: params

  defp merge_map_default(params, key, defaults, provided) do
    current = normalize_optional_map(Map.get(params, key))

    merged =
      cond do
        provided == :unknown and current == %{} ->
          defaults

        provided == :unknown ->
          Map.merge(defaults, current)

        provided_param?(provided, key) ->
          Map.merge(defaults, current)

        true ->
          defaults
      end

    Map.put(params, key, merged)
  end

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp plugin_default(context, key) do
    first_present([
      get_in(context, [:plugin_state, :chat, key]),
      get_in(context, [:plugin_state, :llm, key]),
      get_in(context, [:state, :chat, key]),
      get_in(context, [:state, :llm, key]),
      get_in(context, [:agent, :state, :chat, key]),
      get_in(context, [:agent, :state, :llm, key])
    ])
  end

  defp normalize_optional_map(nil), do: %{}
  defp normalize_optional_map(map) when is_map(map), do: map
  defp normalize_optional_map(map) when is_list(map), do: Map.new(map)
  defp normalize_optional_map(_), do: %{}

  defp merge_optional_maps(left, right), do: Map.merge(left, right)

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}

  defp format_result(result) do
    %{
      text: result.text,
      model: result.model,
      usage: result.usage || Helpers.extract_usage(%{})
    }
  end
end
