defmodule Mix.Tasks.Jido.Ai.StreamText do
  @shortdoc "Test stream_text functionality"
  @moduledoc """
  Simple test task for the stream_text method.

  ## Usage

      mix jido.ai.stream_text "Hello world"
      mix jido.ai.stream_text "Hello world" --model openrouter:openai/gpt-oss-20b:free
      mix jido.ai.stream_text "Hello world" --model openrouter:openai/gpt-oss-20b:free --system "You are helpful"

  ## Options

    * `--model` - Model to use (default: "openrouter:openai/gpt-oss-20b:free")
    * `--system` - System prompt to use
    * `--max-tokens` - Maximum tokens to generate (default: 100)

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_ai)

    {opts, args_list, _} =
      OptionParser.parse(args,
        switches: [
          model: :string,
          system: :string,
          max_tokens: :integer
        ]
      )

    prompt =
      case args_list do
        [p | _] -> p
        [] -> nil
      end

    if is_nil(prompt) do
      IO.puts("Error: Please provide a prompt")
      IO.puts("Usage: mix jido.ai.stream_text \"Your prompt here\"")
      System.halt(1)
    end

    default_model = Application.get_env(:jido_ai, :default_model, "openrouter:openai/gpt-oss-20b:free")
    model = Keyword.get(opts, :model, default_model)
    system_prompt = Keyword.get(opts, :system)
    max_tokens = Keyword.get(opts, :max_tokens, 100)

    stream_opts = [max_tokens: max_tokens]
    stream_opts = if system_prompt, do: Keyword.put(stream_opts, :system_prompt, system_prompt), else: stream_opts

    IO.puts("Jido AI Stream Test")
    IO.puts("==================")
    IO.puts("Model: #{model}")
    if system_prompt, do: IO.puts("System: #{system_prompt}")
    IO.puts("Prompt: #{prompt}")
    IO.puts("")
    IO.puts("LLM Response:")
    IO.puts("-------------")

    case Jido.AI.stream_text(model, prompt, stream_opts) do
      {:ok, stream} ->
        stream
        |> Enum.each(fn chunk ->
          IO.write(chunk)
        end)

        IO.puts("")
        IO.puts("-------------")
        IO.puts("Stream completed successfully")

      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
        System.halt(1)
    end
  end
end
