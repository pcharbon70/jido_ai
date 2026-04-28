defmodule Jido.AI.Integration.BackendBoundaryPhase1Test do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.AI.Backend
  alias Jido.AI.Backend.{Capabilities, Request}
  alias Jido.AI.Error
  alias Jido.AI.TestSupport.FakeReqLLM

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echo input text",
      schema: Zoi.object(%{text: Zoi.string()})

    @impl true
    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule Phase1Agent do
    use Jido.AI.Agent,
      name: "phase1_backend_boundary_agent",
      tools: [EchoTool]
  end

  defmodule TextOnlyBackend do
    @behaviour Backend

    @impl true
    def id, do: :text_only

    @impl true
    def capabilities do
      Capabilities.new(text_generation: true, message_history: true)
    end

    @impl true
    def generate(_request), do: {:ok, :unused}

    @impl true
    def stream(_request), do: {:ok, []}

    @impl true
    def cancel(_token, _opts), do: :ok
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    FakeReqLLM.setup_stubs(%{})
    :ok
  end

  describe "backend boundary request and capability scenarios" do
    test "backend request carries prompt, messages, system prompt, timeout, and tool intent in one shape" do
      request =
        Request.new(
          prompt: "Summarize this",
          messages: [%{role: :user, content: "Summarize this"}],
          system_prompt: "Be concise",
          timeout_ms: 7_500,
          tool_intent: %{allowed_tools: ["echo"], tool_choice: :auto}
        )

      assert request.prompt == "Summarize this"
      assert request.messages == [%{role: :user, content: "Summarize this"}]
      assert request.system_prompt == "Be concise"
      assert request.timeout_ms == 7_500
      assert request.tool_intent.allowed_tools == ["echo"]
      assert request.tool_intent.tool_choice == :auto
    end

    test "capability checks reject unsupported combinations before runtime execution begins" do
      request =
        Request.new(
          backend: :text_only,
          operation: :object,
          stream?: true,
          messages: [%{role: :user, content: "Hello"}]
        )

      assert {:error, %Error.Backend.UnsupportedCapability{} = error} =
               Backend.validate_request(TextOnlyBackend, request)

      assert error.backend == :text_only
      assert error.capability == :streaming
    end
  end

  describe "default backend compatibility" do
    test "ReqLLM remains the default backend for direct facades when no backend is selected" do
      assert {:ok, %{message: %{content: "Stubbed response for: hello"}}} = AI.generate_text("hello")
    end

    test "request-handle ask and await orchestration still behaves as before on the default backend" do
      {:ok, pid} = Jido.AgentServer.start_link(agent: Phase1Agent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      assert {:ok, request} = Phase1Agent.ask(pid, "hello", timeout: 5_000)
      assert request.status == :pending
      assert {:ok, "Stubbed stream for: hello"} = Phase1Agent.await(request, timeout: 5_000)
    end

    test "explicit req_llm backend override preserves existing request behavior" do
      {:ok, pid} = Jido.AgentServer.start_link(agent: Phase1Agent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      assert {:ok, "Stubbed stream for: hello"} =
               Phase1Agent.ask_sync(pid, "hello", backend: :req_llm, timeout: 5_000)
    end
  end
end
