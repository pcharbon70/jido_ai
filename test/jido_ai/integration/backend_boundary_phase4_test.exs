defmodule Jido.AI.Integration.BackendBoundaryPhase4Test do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.AI.Backend.Request
  alias Jido.AI.Backends
  alias Jido.AI.Directive.LLMGenerate
  alias Jido.AI.Error
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Config
  alias Jido.AI.TestSupport.DirectiveExec, as: DirectiveSupport
  alias Jido.AI.TestSupport.FakeReqLLM
  alias Jido.AgentServer.DirectiveExec

  defmodule CalculatorTool do
    use Jido.Action,
      name: "calculator",
      description: "Phase 4 integration calculator",
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
    old_backend = Application.get_env(:jido_ai, :llm_backend)
    old_backends = Application.get_env(:jido_ai, :llm_backends)
    old_aliases = Application.get_env(:jido_ai, :model_aliases)
    old_defaults = Application.get_env(:jido_ai, :llm_defaults)

    on_exit(fn ->
      restore_env(:llm_backend, old_backend)
      restore_env(:llm_backends, old_backends)
      restore_env(:model_aliases, old_aliases)
      restore_env(:llm_defaults, old_defaults)
    end)

    FakeReqLLM.setup_stubs(%{})
    :ok
  end

  describe "harness adapter runtime scenarios" do
    test "translates harness requests and event streams through directive and runtime boundaries" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(Jido.Harness, :capabilities, fn :codex ->
        {:ok, %Jido.Harness.Capabilities{cancellation?: false}}
      end)

      Mimic.stub(Jido.Harness, :run_request, fn :codex, %Jido.Harness.RunRequest{} = run_request, [] ->
        case run_request.metadata["request_id"] do
          "phase4_directive" ->
            assert run_request.prompt == "Summarize the workspace"
            assert run_request.system_prompt == "Keep it brief"
            assert run_request.cwd == "/tmp/phase4"
            assert run_request.attachments == ["/tmp/phase4/notes.md"]

            {:ok,
             [
               Jido.Harness.Event.new!(%{
                 type: :usage,
                 provider: :codex,
                 session_id: "sess_phase4_directive",
                 payload: %{"input_tokens" => 4, "output_tokens" => 5}
               }),
               Jido.Harness.Event.new!(%{
                 type: :final,
                 provider: :codex,
                 session_id: "sess_phase4_directive",
                 payload: %{"text" => "Directive answer", "finish_reason" => "completed"}
               })
             ]}

          "phase4_runtime" ->
            assert run_request.prompt == "Summarize the repo"
            assert run_request.system_prompt == "Use one sentence"
            assert run_request.cwd == "/tmp/phase4"
            assert run_request.metadata["run_id"] == "run_phase4_runtime"

            {:ok,
             [
               Jido.Harness.Event.new!(%{
                 type: :session_started,
                 provider: :codex,
                 session_id: "sess_phase4_runtime",
                 timestamp: "2026-04-29T15:00:00Z",
                 payload: %{}
               }),
               Jido.Harness.Event.new!(%{
                 type: :usage,
                 provider: :codex,
                 session_id: "sess_phase4_runtime",
                 payload: %{"input_tokens" => 6, "output_tokens" => 8}
               }),
               Jido.Harness.Event.new!(%{
                 type: :final,
                 provider: :codex,
                 session_id: "sess_phase4_runtime",
                 payload: %{"text" => "Runtime answer", "finish_reason" => "completed"}
               })
             ]}

          other ->
            flunk("unexpected harness request id: #{inspect(other)}")
        end
      end)

      directive =
        LLMGenerate.new!(%{
          id: "phase4_directive",
          backend: :harness,
          system_prompt: "Keep it brief",
          context: [%{role: :user, content: "Summarize the workspace"}],
          workspace: %{cwd: "/tmp/phase4", attachments: [%{path: "/tmp/phase4/notes.md"}]},
          backend_metadata: %{provider: :codex}
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      usage_signal = DirectiveSupport.assert_signal_cast("ai.usage")
      assert usage_signal.data.call_id == "phase4_directive"
      assert usage_signal.data.total_tokens == 9

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:ok, turn, []} = response_signal.data.result
      assert turn.text == "Directive answer"
      assert response_signal.data.metadata == %{origin: :directive, operation: :generate_text}

      config =
        Config.new(%{
          backend: :harness,
          system_prompt: "Use one sentence",
          workspace: %{cwd: "/tmp/phase4"},
          backend_metadata: %{provider: :codex},
          tools: %{}
        })

      events =
        ReAct.stream("Summarize the repo", config,
          request_id: "phase4_runtime",
          run_id: "run_phase4_runtime"
        )
        |> Enum.to_list()

      assert Enum.all?(events, &match?(%Jido.AI.Reasoning.ReAct.Event{}, &1))
      assert Enum.any?(events, &(&1.kind == :llm_started))

      assert Enum.find(events, &(&1.kind == :request_completed)).data == %{
               result: "Runtime answer",
               termination_reason: :final_answer,
               usage: %{input_tokens: 6, output_tokens: 8, total_tokens: 14}
             }
    end

    test "cancels harness-backed runtime streams through canonical cleanup" do
      Mimic.stub(Jido.Harness, :capabilities, fn :codex ->
        {:ok, %Jido.Harness.Capabilities{cancellation?: true}}
      end)

      Mimic.stub(Jido.Harness, :run_request, fn :codex, %Jido.Harness.RunRequest{} = run_request, [] ->
        assert run_request.metadata["request_id"] == "phase4_cancel"

        stream =
          Stream.concat(
            [
              Jido.Harness.Event.new!(%{
                type: :session_started,
                provider: :codex,
                session_id: "sess_phase4_cancel",
                payload: %{}
              })
            ],
            Stream.repeatedly(fn ->
              Process.sleep(5)

              Jido.Harness.Event.new!(%{
                type: :text_delta,
                provider: :codex,
                session_id: "sess_phase4_cancel",
                payload: %{"delta" => "x"}
              })
            end)
          )

        {:ok, stream}
      end)

      Mimic.stub(Jido.Harness, :cancel, fn :codex, "sess_phase4_cancel" ->
        :ok
      end)

      {:ok, task_supervisor} = Task.Supervisor.start_link()
      on_exit(fn -> if Process.alive?(task_supervisor), do: Process.exit(task_supervisor, :shutdown) end)

      config =
        Config.new(%{
          backend: :harness,
          workspace: %{cwd: "/tmp/phase4"},
          backend_metadata: %{provider: :codex},
          tools: %{}
        })

      [first_event, second_event, third_event] =
        ReAct.stream("cancel me", config,
          request_id: "phase4_cancel",
          run_id: "run_phase4_cancel",
          task_supervisor: task_supervisor
        )
        |> Enum.take(3)

      assert first_event.kind == :request_started
      assert second_event.kind == :llm_started
      assert third_event.kind == :llm_delta

      assert wait_until(fn ->
               Task.Supervisor.children(task_supervisor) == []
             end)
    end
  end

  describe "unsupported capability and fallback scenarios" do
    test "returns typed unsupported-capability errors for structured output, embeddings, and message history" do
      object_request =
        Request.new(%{
          backend: :harness,
          operation: :object,
          prompt: "extract fields",
          response_schema: %{type: "object"},
          workspace: %{cwd: "/tmp/phase4"}
        })

      embedding_request =
        Request.new(%{
          backend: :harness,
          operation: :embedding,
          inputs: ["hello"],
          workspace: %{cwd: "/tmp/phase4"}
        })

      history_request =
        Request.new(%{
          backend: :harness,
          operation: :text,
          messages: [
            %{role: :user, content: "hello"},
            %{role: :assistant, content: "hi again"}
          ],
          workspace: %{cwd: "/tmp/phase4"}
        })

      assert {:error, %Error.Backend.UnsupportedCapability{} = object_error} = Backends.generate(object_request)
      assert object_error.capability == :structured_output
      assert object_error.operation == :object

      assert {:error, %Error.Backend.UnsupportedCapability{} = embedding_error} = Backends.generate(embedding_request)
      assert embedding_error.capability == :embeddings
      assert embedding_error.operation == :embedding

      assert {:error, %Error.Backend.UnsupportedCapability{} = history_error} = Backends.generate(history_request)
      assert history_error.capability == :message_history
      assert history_error.operation == :text
    end

    test "fails explicit local-tool parity gaps without changing default facade behavior" do
      config =
        Config.new(%{
          backend: :harness,
          system_prompt: "Use tools if needed",
          workspace: %{cwd: "/tmp/phase4"},
          backend_metadata: %{provider: :codex},
          tools: %{CalculatorTool.name() => CalculatorTool}
        })

      events =
        ReAct.stream("What is 2 + 2?", config,
          request_id: "phase4_local_tools",
          run_id: "run_phase4_local_tools"
        )
        |> Enum.to_list()

      assert Enum.any?(events, fn
               %{kind: :request_failed, data: %{error: %Error.Backend.UnsupportedCapability{} = error}} ->
                 error.backend == :harness and error.capability == :local_tools and error.operation == :text

               _ ->
                 false
             end)

      schema = %{type: "object", properties: %{"name" => %{type: "string"}}}

      assert {:ok, response} = AI.generate_text("hello")
      assert response.message.content == "Stubbed response for: hello"

      assert {:ok, object_response} = AI.generate_object("extract", schema)
      assert object_response.object == %{name: "stubbed", model: AI.resolve_model(:thinking)}

      assert {:error, %Error.Backend.UnsupportedBackend{} = error} =
               AI.generate_text("hello", backend: :harness)

      assert error.backend == :harness
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
