defmodule Jido.AI.Integration.BackendBoundaryPhase3Test do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Backend
  alias Jido.AI.Backend.{Capabilities, Request}
  alias Jido.AI.Backends
  alias Jido.AI.Directive.{LLMGenerate, LLMStream}
  alias Jido.AI.Error
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Config
  alias Jido.AI.TestSupport.DirectiveExec, as: DirectiveSupport
  alias Jido.AI.TestSupport.FakeReqLLM
  alias Jido.AI.{ToolAdapter, Turn}
  alias Jido.AgentServer.DirectiveExec

  defmodule CalculatorTool do
    use Jido.Action,
      name: "calculator",
      description: "Phase 3 integration calculator",
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

  defmodule ToollessBackend do
    @behaviour Backend

    @impl true
    def id, do: :toolless

    @impl true
    def capabilities do
      Capabilities.new(text_generation: true, message_history: true)
    end

    @impl true
    def generate(request) do
      case Backend.validate_request(__MODULE__, request) do
        :ok -> {:ok, :unused}
        {:error, _} = error -> error
      end
    end

    @impl true
    def stream(_request), do: {:ok, []}

    @impl true
    def cancel(_token, _opts), do: :ok
  end

  setup :set_mimic_from_context

  setup do
    old_backends = Application.get_env(:jido_ai, :llm_backends)

    on_exit(fn ->
      restore_env(:llm_backends, old_backends)
    end)

    FakeReqLLM.setup_stubs(%{})
    :ok
  end

  describe "directive and runtime normalization scenarios" do
    test "directives preserve canonical ai.llm signals through backend result and stream translation" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      state = DirectiveSupport.state_with_supervisor(supervisor)

      generate =
        LLMGenerate.new!(%{
          id: "phase3_generate",
          model: "test:phase3-generate",
          context: [%{role: :user, content: "hello"}]
        })

      assert {:async, nil, ^state} = DirectiveExec.exec(generate, nil, state)

      usage_signal = DirectiveSupport.assert_signal_cast("ai.usage")
      assert usage_signal.data.call_id == "phase3_generate"
      assert usage_signal.data.total_tokens == 36

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:ok, %Turn{text: "Stubbed response for: hello"}, []} = response_signal.data.result
      assert response_signal.data.metadata == %{origin: :directive, operation: :generate_text}

      stream =
        LLMStream.new!(%{
          id: "phase3_stream",
          model: "test:phase3-stream",
          context: [%{role: :user, content: "hello"}]
        })

      assert {:async, nil, ^state} = DirectiveExec.exec(stream, nil, state)

      delta_signal = DirectiveSupport.assert_signal_cast("ai.llm.delta")
      assert delta_signal.data.call_id == "phase3_stream"
      assert delta_signal.data.chunk_type == :content
      assert delta_signal.data.delta == "Stubbed stream for: hello"

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:ok, %Turn{text: "Stubbed stream for: hello"}, []} = response_signal.data.result
      assert response_signal.data.metadata == %{origin: :directive, operation: :stream_text}
    end

    test "ReAct runtime preserves request correlation and stream cancellation through backend event translation" do
      config = Config.new(%{model: :capable, tools: %{}})

      events =
        ReAct.stream("Say hello", config, request_id: "req_phase3_runtime", run_id: "run_phase3_runtime")
        |> Enum.to_list()

      assert Enum.all?(events, &(&1.request_id == "req_phase3_runtime"))
      assert Enum.all?(events, &(&1.run_id == "run_phase3_runtime"))
      assert Enum.any?(events, &(&1.kind == :llm_started))
      assert Enum.any?(events, &(&1.kind == :llm_delta))
      assert Enum.find(events, &(&1.kind == :request_completed)).data.result == "Stubbed stream for: Say hello"

      parent = self()

      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        infinite_stream =
          Stream.repeatedly(fn ->
            Process.sleep(5)
            ReqLLM.StreamChunk.text("x")
          end)

        {:ok,
         %{
           stream: infinite_stream,
           finish_reason: :stop,
           usage: %{input_tokens: 1, output_tokens: 1},
           model: model,
           cancel: fn ->
             send(parent, :phase3_stream_cancelled)
             :ok
           end
         }}
      end)

      {:ok, task_supervisor} = Task.Supervisor.start_link()
      on_exit(fn -> if Process.alive?(task_supervisor), do: Process.exit(task_supervisor, :shutdown) end)

      [first_event] =
        ReAct.stream("cancel me", config, task_supervisor: task_supervisor)
        |> Enum.take(1)

      assert first_event.kind == :request_started
      assert_receive :phase3_stream_cancelled, 200

      assert wait_until(fn ->
               Task.Supervisor.children(task_supervisor) == []
             end)
    end
  end

  describe "turn and tool normalization scenarios" do
    test "canonical turn and tool loop accept normalized backend results and manifests" do
      manifest = ToolAdapter.to_manifest(CalculatorTool)

      turn =
        Turn.from_result_map(%{
          tool_calls: [
            %{
              id: "tc_phase3_calc",
              name: "calculator",
              arguments: %{"operation" => "add", "a" => 5, "b" => 3}
            }
          ],
          finish_reason: :tool_calls,
          message_metadata: %{response_id: "resp_phase3_calc"}
        })

      assert Turn.needs_tools?(turn)

      assert {:ok, turn_with_results} = Turn.run_tools(turn, %{tools: [manifest]})

      assistant_message = Turn.assistant_message(turn_with_results)
      [tool_message] = Turn.tool_messages(turn_with_results)

      assert assistant_message.metadata == %{response_id: "resp_phase3_calc"}
      assert ReqLLM.ToolCall.args_map(hd(assistant_message.tool_calls)) == %{"operation" => "add", "a" => 5, "b" => 3}

      assert Jason.decode!(Turn.extract_from_content(tool_message.content)) == %{
               "ok" => true,
               "result" => %{"result" => 8}
             }
    end

    test "non-tool-capable backends fail with typed unsupported outcomes" do
      Application.put_env(:jido_ai, :llm_backends, %{
        toolless: %{adapter: ToollessBackend}
      })

      request =
        Request.new(%{
          backend: :toolless,
          operation: :text,
          prompt: "hello",
          tool_intent: %{tools: [CalculatorTool], tool_choice: :auto}
        })

      assert {:error, %Error.Backend.UnsupportedCapability{} = error} = Backends.generate(request)
      assert error.backend == :toolless
      assert error.capability == :local_tools
      assert error.operation == :text
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_ai, key)
  defp restore_env(key, value), do: Application.put_env(:jido_ai, key, value)

  defp wait_until(fun, attempts \\ 40)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) when is_function(fun, 0) do
    if fun.() do
      true
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end
end
