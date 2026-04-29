defmodule Jido.AI.Integration.BackendBoundaryPhase5Test do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Error
  alias Jido.AI.Plugins.Chat, as: ChatPlugin
  alias Jido.AI.Plugins.Planning, as: PlanningPlugin
  alias Jido.AI.Plugins.Reasoning.ChainOfThought, as: CoTPlugin
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Config
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.TestSupport.BackendMatrix
  alias Jido.AI.TestSupport.FakeReqLLM
  alias Jido.Signal

  setup :set_mimic_from_context

  setup do
    old_env = BackendMatrix.snapshot_jido_ai_env()

    on_exit(fn ->
      BackendMatrix.restore_jido_ai_env(old_env)
    end)

    Application.put_env(:jido_ai, :llm_backend, :req_llm)
    Application.put_env(:jido_ai, :llm_backends, %{harness: BackendMatrix.harness_backend_config(%{provider: :codex})})

    FakeReqLLM.setup_stubs(%{})
    :ok
  end

  describe "strategy and plugin backend adoption scenarios" do
    test "preserves ReqLLM-default behavior for runtime streams and delegated reasoning runners" do
      config = Config.new(%{model: :capable, tools: %{}})

      events =
        ReAct.stream("Say hello", config, request_id: "phase5_reqllm_runtime", run_id: "phase5_reqllm_runtime")
        |> Enum.to_list()

      assert Enum.any?(events, &(&1.kind == :request_started))
      assert Enum.any?(events, &(&1.kind == :llm_started))

      request_completed = Enum.find(events, &(&1.kind == :request_completed))

      assert request_completed.data.result == "Stubbed stream for: Say hello"
      assert request_completed.data.termination_reason == :final_answer
      assert is_map(request_completed.data.usage)

      assert {:ok, payload} =
               RunStrategy.run(%{strategy: :cot, prompt: "Explain 2+2", timeout: 750}, %{})

      assert payload.strategy == :cot
      assert payload.status == :success
      assert is_map(payload.usage)
    end

    test "allows compatible chat and planning plugin routes to opt into harness without changing route contracts" do
      Mimic.stub(Jido.Harness, :capabilities, fn :codex ->
        {:ok, %Jido.Harness.Capabilities{cancellation?: false}}
      end)

      Mimic.stub(Jido.Harness, :run_request, fn :codex, %Jido.Harness.RunRequest{} = run_request, [] ->
        case run_request.prompt do
          "Summarize the repo" ->
            assert run_request.system_prompt == "Keep it brief"
            assert run_request.cwd == "/tmp/plugin_chat"

            {:ok,
             [
               Jido.Harness.Event.new!(%{
                 type: :usage,
                 provider: :codex,
                 session_id: "sess_phase5_chat",
                 payload: %{"input_tokens" => 2, "output_tokens" => 3}
               }),
               Jido.Harness.Event.new!(%{
                 type: :final,
                 provider: :codex,
                 session_id: "sess_phase5_chat",
                 payload: %{"text" => "Harness chat answer", "finish_reason" => "completed"}
               })
             ]}

          <<"Goal: Ship a release", _::binary>> ->
            assert run_request.system_prompt =~ "expert strategic planner"
            assert run_request.cwd == "/tmp/plugin_plan"

            {:ok,
             [
               Jido.Harness.Event.new!(%{
                 type: :usage,
                 provider: :codex,
                 session_id: "sess_phase5_plan",
                 payload: %{"input_tokens" => 4, "output_tokens" => 6}
               }),
               Jido.Harness.Event.new!(%{
                 type: :final,
                 provider: :codex,
                 session_id: "sess_phase5_plan",
                 payload: %{"text" => "Harness planning answer", "finish_reason" => "completed"}
               })
             ]}

          other ->
            flunk("unexpected harness prompt: #{inspect(other)}")
        end
      end)

      chat_action = route_action(ChatPlugin, "chat.simple")
      plan_action = route_action(PlanningPlugin, "planning.plan")

      chat_context = %{
        provided_params: [:prompt],
        plugin_state: %{
          chat: %{
            default_model: :capable,
            default_system_prompt: "Keep it brief",
            backend: :harness,
            workspace: %{cwd: "/tmp/plugin_chat"},
            backend_metadata: %{provider: :codex}
          }
        }
      }

      planning_context = %{
        provided_params: [:goal],
        plugin_state: %{
          planning: %{
            default_model: :planning,
            backend: :harness,
            workspace: %{cwd: "/tmp/plugin_plan"},
            backend_metadata: %{provider: :codex}
          }
        }
      }

      assert chat_action == Jido.AI.Actions.LLM.Chat
      assert plan_action == Jido.AI.Actions.Planning.Plan

      assert {:ok, chat_result} = chat_action.run(%{prompt: "Summarize the repo"}, chat_context)
      assert chat_result.text == "Harness chat answer"
      assert chat_result.usage == %{input_tokens: 2, output_tokens: 3, total_tokens: 5}

      assert {:ok, plan_result} = plan_action.run(%{goal: "Ship a release"}, planning_context)
      assert plan_result.plan == "Harness planning answer"
      assert plan_result.goal == "Ship a release"
    end

    test "keeps unsupported backend selections typed for strategy and plugin-only capability gaps" do
      signal =
        Signal.new!("reasoning.cot.run", %{prompt: "Explain 2+2", backend: :harness}, source: "/test")

      assert {:ok, {:override, {RunStrategy, params}}} = CoTPlugin.handle_signal(signal, %{})

      assert {:error, %Error.Backend.UnsupportedBackend{} = strategy_error} =
               RunStrategy.run(params, %{provided_params: [:prompt, :backend, :strategy]})

      assert strategy_error.backend == :harness
      assert strategy_error.supported_backends == [:req_llm]

      tool_action = route_action(ChatPlugin, "chat.message")

      tool_context = %{
        provided_params: [:prompt],
        plugin_state: %{
          chat: %{
            default_model: :capable,
            backend: :harness,
            workspace: %{cwd: "/tmp/plugin_chat"},
            backend_metadata: %{provider: :codex}
          }
        },
        tools: %{}
      }

      assert {:error, %Error.Backend.UnsupportedCapability{} = tool_error} =
               tool_action.run(%{prompt: "Use tools if needed"}, tool_context)

      assert tool_error.backend == :harness
      assert tool_error.capability == :message_history
      assert tool_error.operation == :text
    end
  end

  describe "rollout convergence scenarios" do
    test "documents the final backend matrix and keeps spec workspace references coherent" do
      assert File.read!("README.md") =~ "ReqLLM remains the default execution path"

      assert File.read!("guides/developer/configuration_reference.md") =~
               "Strategy plugins and `Jido.AI.Actions.Reasoning.RunStrategy` stay ReqLLM-default"

      assert File.read!("guides/developer/plugins_and_actions_composition.md") =~ "Backend-Aware Plugin Defaults"
      assert File.read!("guides/user/package_overview.md") =~ "backend boundary: ReqLLM default"
      assert File.read!("usage-rules.md") =~ "typed unsupported-backend or unsupported-capability outcomes"
      assert File.read!("AGENTS.md") =~ "Keep ReqLLM as the default for strategy runners"

      assert File.read!(".spec/decisions/jido_ai.llm_backend_boundary.md") =~
               "repo-owned backend-matrix test helpers"

      assert File.read!(".spec/planning/README.md") =~ "Phase 5 - Strategy, Plugin, and Rollout Convergence"

      assert File.read!(".spec/specs/plugins_and_capabilities.spec.md") =~
               "capability_gated_backend_adoption"
    end
  end

  defp route_action(plugin, signal_type) do
    plugin
    |> signal_routes_for()
    |> Map.new()
    |> Map.fetch!(signal_type)
  end

  defp signal_routes_for(plugin), do: plugin.signal_routes(%{})
end
