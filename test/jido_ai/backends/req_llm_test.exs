defmodule Jido.AI.Backends.ReqLLMTest do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI
  alias Jido.AI.Backend.Request
  alias Jido.AI.Backend.Result
  alias Jido.AI.Backends
  alias Jido.AI.Backends.ReqLLM, as: ReqLLMBackend

  defmodule CalculatorTool do
    use Jido.Action,
      name: "calculator",
      description: "Adapter test calculator",
      schema:
        Zoi.object(%{
          operation: Zoi.string(),
          a: Zoi.integer(),
          b: Zoi.integer()
        })

    @impl true
    def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, %{result: a + b}}
    def run(_params, _context), do: {:error, :unsupported_operation}
  end

  setup :set_mimic_from_context

  describe "adapter lookup" do
    test "resolves the ReqLLM adapter for the default backend" do
      assert Backends.adapter_for(:req_llm) == ReqLLMBackend
    end
  end

  describe "generate/1" do
    test "generates normalized text results and centralizes ReqLLM option shaping" do
      expect(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == AI.resolve_model(:fast)
        assert Enum.map(messages, & &1.role) == [:system, :user]
        assert hd(Enum.at(messages, 0).content).text == "System"
        assert hd(Enum.at(messages, 1).content).text == "hello"
        assert opts[:max_tokens] == 99
        assert opts[:temperature] == 0.4
        assert opts[:receive_timeout] == 777
        assert opts[:req_http_options] == [plug: {Req.Test, []}]
        assert opts[:tool_choice] == :auto
        assert opts[:foo] == :bar
        assert [tool] = opts[:tools]
        assert tool.name == "calculator"

        {:ok,
         %{
           message: %{content: "adapter text", tool_calls: []},
           finish_reason: :stop,
           usage: %{input_tokens: 2, output_tokens: 3},
           model: model
         }}
      end)

      request =
        Request.new(
          operation: :text,
          model: :fast,
          prompt: "hello",
          system_prompt: "System",
          max_tokens: 99,
          temperature: 0.4,
          timeout_ms: 777,
          tool_intent: %{tools: [CalculatorTool], tool_choice: :auto},
          backend_metadata: %{
            req_http_options: [plug: {Req.Test, []}],
            opts: [foo: :bar]
          }
        )

      assert {:ok, %Result{} = result} = ReqLLMBackend.generate(request)
      assert result.backend == :req_llm
      assert result.operation == :text
      assert result.text == "adapter text"
      assert result.model == AI.resolve_model(:fast)
      assert result.usage == %{input_tokens: 2, output_tokens: 3, total_tokens: 5}
      assert ReqLLMBackend.raw_result(result).message.content == "adapter text"
    end

    test "generates normalized object results" do
      schema = %{type: "object", properties: %{"name" => %{type: "string"}}}

      expect(ReqLLM.Generation, :generate_object, fn model, messages, object_schema, opts ->
        assert model == AI.resolve_model(:thinking)
        assert Enum.map(messages, & &1.role) == [:user]
        assert hd(Enum.at(messages, 0).content).text == "extract"
        assert object_schema == schema
        assert opts[:max_tokens] == 222
        assert opts[:receive_timeout] == 888
        {:ok, %{object: %{"name" => "Alice"}, usage: %{input_tokens: 1, output_tokens: 2}, model: model}}
      end)

      request =
        Request.new(
          operation: :object,
          model: :thinking,
          prompt: "extract",
          response_schema: schema,
          max_tokens: 222,
          timeout_ms: 888
        )

      assert {:ok, %Result{} = result} = ReqLLMBackend.generate(request)
      assert result.operation == :object
      assert result.object == %{"name" => "Alice"}
      assert result.model == AI.resolve_model(:thinking)
      assert result.usage == %{input_tokens: 1, output_tokens: 2, total_tokens: 3}
    end

    test "generates normalized embedding results" do
      expect(ReqLLM.Embedding, :embed, fn model, texts, opts ->
        assert model == AI.resolve_model(:embedding)
        assert texts == ["alpha", "beta"]
        assert opts[:dimensions] == 2
        assert opts[:receive_timeout] == 444
        {:ok, [[0.1, 0.2], [0.3, 0.4]]}
      end)

      request =
        Request.new(
          operation: :embedding,
          model: :embedding,
          inputs: ["alpha", "beta"],
          timeout_ms: 444,
          backend_metadata: %{dimensions: 2}
        )

      assert {:ok, %Result{} = result} = ReqLLMBackend.generate(request)
      assert result.operation == :embedding
      assert result.embeddings == [[0.1, 0.2], [0.3, 0.4]]
      assert result.model == AI.resolve_model(:embedding)
      assert result.metadata == %{count: 2, dimensions: 2}
    end
  end

  describe "stream/1" do
    test "preserves current ReqLLM stream semantics for the default path" do
      expect(ReqLLM, :stream_text, fn model, messages, opts ->
        assert model == AI.resolve_model(:fast)
        assert Enum.map(messages, & &1.role) == [:user]
        assert hd(Enum.at(messages, 0).content).text == "stream"
        assert opts[:max_tokens] == 10
        {:ok, %{stream: [:chunk]}}
      end)

      request =
        Request.new(
          operation: :text,
          model: :fast,
          prompt: "stream",
          max_tokens: 10
        )

      assert {:ok, %{stream: [:chunk]}} = ReqLLMBackend.stream(request)
    end
  end
end
