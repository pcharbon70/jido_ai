defmodule Jido.AI.Integration.BackendBoundaryPhase2Test do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.AI.Actions.LLM.{Chat, Complete, Embed, GenerateObject}
  alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}
  alias Jido.AI.Actions.Reasoning.{Analyze, Explain, Infer}
  alias Jido.AI.Actions.ToolCalling.CallWithTools
  alias Jido.AI.TestSupport.BackendMatrix
  alias Jido.AI.TestSupport.FakeReqLLM

  defmodule CalculatorTool do
    use Jido.Action,
      name: "calculator",
      description: "Integration calculator",
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

  setup do
    old_env = BackendMatrix.snapshot_jido_ai_env([:model_aliases, :llm_defaults])

    on_exit(fn ->
      BackendMatrix.restore_jido_ai_env(old_env)
    end)

    FakeReqLLM.setup_stubs(%{})

    Mimic.stub(ReqLLM.Embedding, :embed, fn model, texts, opts ->
      dimensions = Keyword.get(opts, :dimensions, 3)
      embedding = Enum.map(1..dimensions, &(&1 / 10))

      {:ok,
       %{
         embeddings: Enum.map(texts, fn _ -> embedding end),
         model: model
       }}
    end)

    :ok
  end

  describe "facade parity integration" do
    test "top-level facades preserve raw default shapes and configured defaults through the adapter" do
      Application.put_env(:jido_ai, :model_aliases, %{
        capable: "test:facade-text-model",
        thinking: "test:facade-object-model",
        fast: "test:facade-stream-model"
      })

      Application.put_env(:jido_ai, :llm_defaults, %{
        text: %{model: :capable},
        object: %{model: :thinking},
        stream: %{model: :fast}
      })

      schema = %{type: "object", properties: %{"name" => %{type: "string"}}}

      assert {:ok, text_response} = AI.generate_text("hello")
      assert text_response.message.content == "Stubbed response for: hello"
      assert text_response.model == "test:facade-text-model"

      assert {:ok, object_response} = AI.generate_object("extract", schema)
      assert object_response.object == %{name: "stubbed", model: "test:facade-object-model"}
      assert object_response.model == "test:facade-object-model"

      assert {:ok, "Stubbed response for: hello"} = AI.ask("hello")

      assert {:ok, stream_response} = AI.stream_text("hello")
      assert stream_response.chunks == ["Stubbed ", "stream ", "for ", "hello"]
      assert stream_response.final.message.content == "Stubbed stream for hello"
      assert stream_response.final.model == "test:facade-stream-model"
    end
  end

  describe "standalone action parity integration" do
    test "llm actions preserve normalized result maps through the backend adapter" do
      schema = %{type: "object", properties: %{"name" => %{type: "string"}}}

      assert {:ok, chat} = Chat.run(%{prompt: "hello"}, %{})
      assert chat.text == "Stubbed response for: hello"
      assert chat.model == AI.resolve_model(:fast)
      assert chat.usage.total_tokens > 0

      assert {:ok, complete} = Complete.run(%{prompt: "finish this"}, %{})
      assert complete.text == "Stubbed response for: finish this"
      assert complete.model == AI.resolve_model(:fast)

      assert {:ok, object_result} =
               GenerateObject.run(%{prompt: "Generate a person", object_schema: schema}, %{})

      assert object_result.object == %{name: "stubbed", model: AI.resolve_model(:fast)}
      assert object_result.model == AI.resolve_model(:fast)

      assert {:ok, embed} = Embed.run(%{texts_list: ["alpha", "beta"], dimensions: 2}, %{})
      assert embed.count == 2
      assert embed.dimensions == 2
      assert embed.model == AI.resolve_model(:embedding)
      assert embed.embeddings == [[0.1, 0.2], [0.1, 0.2]]
    end

    test "planning and prompt reasoning actions preserve existing normalized contracts" do
      assert {:ok, plan} = Plan.run(%{goal: "Ship a release"}, %{})
      assert plan.model == AI.resolve_model(:planning)
      assert plan.goal == "Ship a release"
      assert is_list(plan.steps)

      assert {:ok, decomposition} = Decompose.run(%{goal: "Launch a product"}, %{})
      assert decomposition.model == AI.resolve_model(:planning)
      assert decomposition.goal == "Launch a product"
      assert decomposition.depth == 3

      assert {:ok, prioritization} =
               Prioritize.run(%{tasks: ["Fix bug", "Write docs", "Ship patch"]}, %{})

      assert prioritization.model == AI.resolve_model(:planning)
      assert is_list(prioritization.ordered_tasks)
      assert is_map(prioritization.scores)

      assert {:ok, analysis} =
               Analyze.run(%{input: "I loved this release.", analysis_type: :sentiment}, %{})

      assert analysis.model == AI.resolve_model(:reasoning)
      assert analysis.analysis_type == :sentiment
      assert analysis.result =~ "Stubbed response for: I loved this release."

      assert {:ok, explanation} =
               Explain.run(%{topic: "Recursion", detail_level: :basic, include_examples: false}, %{})

      assert explanation.model == AI.resolve_model(:reasoning)
      assert explanation.detail_level == :basic
      assert explanation.result =~ "Stubbed response for: Explain: Recursion"

      assert {:ok, inference} =
               Infer.run(%{premises: "All cats are mammals.", question: "Are cats mammals?"}, %{})

      assert inference.model == AI.resolve_model(:reasoning)
      assert inference.reasoning == inference.result
      assert inference.result =~ "Premises:"
    end

    test "tool-calling action preserves ReqLLM-compatible multi-turn behavior through the adapter" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"],
        auto_execute: true,
        max_tokens: 123,
        temperature: 0.2
      }

      context = %{
        tools: %{CalculatorTool.name() => CalculatorTool}
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :final_answer
      assert result.model == AI.resolve_model(:capable)
      assert result.text =~ "Tool execution complete: 8"
      assert result.text =~ "max_tokens=123"
      assert result.text =~ "temperature=0.2"
      assert is_list(result.messages)
      assert result.usage.total_tokens > 0
    end
  end
end
