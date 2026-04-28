defmodule Jido.AI.BackendTest do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: true

  alias Jido.AI.Backend
  alias Jido.AI.Backend.{Capabilities, Event, Request, Result}
  alias Jido.AI.Error

  defmodule TextBackend do
    @behaviour Backend

    @impl true
    def id, do: :text_backend

    @impl true
    def capabilities do
      Capabilities.new(
        text_generation: true,
        message_history: true
      )
    end

    @impl true
    def generate(_request), do: {:ok, Result.new(backend: :text_backend, text: "ok")}

    @impl true
    def stream(_request), do: {:error, :unsupported}

    @impl true
    def cancel(_token, _opts), do: {:error, :unsupported}
  end

  describe "request modeling" do
    test "normalizes prompt, tool intent, and workspace context into one shape" do
      request =
        Request.new(
          request_id: "req_1",
          backend: :req_llm,
          prompt: "hello",
          messages: [%{role: :user, content: "hello"}],
          system_prompt: "System",
          model: :fast,
          timeout_ms: 5_000,
          tool_intent: [tools: [:calculator], allowed_tools: ["calculator"], tool_choice: :auto],
          workspace: [cwd: "/tmp/demo", attachments: [%{name: "note.txt"}]],
          backend_metadata: %{transport: :api}
        )

      assert request.request_id == "req_1"
      assert request.prompt == "hello"
      assert request.messages == [%{role: :user, content: "hello"}]
      assert request.system_prompt == "System"
      assert request.timeout_ms == 5_000
      assert %Request.ToolIntent{} = request.tool_intent
      assert request.tool_intent.allowed_tools == ["calculator"]
      assert %Request.Workspace{} = request.workspace
      assert request.workspace.cwd == "/tmp/demo"
      assert request.backend_metadata == %{transport: :api}
    end

    test "detects message-history, tool, and workspace requirements" do
      request =
        Request.new(
          messages: [%{role: :user, content: "hello"}],
          tool_intent: %{allowed_tools: ["calculator"]},
          workspace: %{cwd: "/tmp/demo"}
        )

      assert Request.uses_message_history?(request)
      assert Request.needs_local_tools?(request)
      assert Request.needs_workspace?(request)
    end
  end

  describe "capability validation" do
    test "computes required capabilities from request shape" do
      request =
        Request.new(
          operation: :object,
          stream?: true,
          cancellable?: true,
          messages: [%{role: :user, content: "hello"}],
          tool_intent: %{allowed_tools: ["calculator"]},
          workspace: %{cwd: "/tmp/demo"}
        )

      assert Enum.sort(Capabilities.required_for(request)) == [
               :cancellation,
               :local_tools,
               :message_history,
               :streaming,
               :structured_output,
               :workspace_execution
             ]
    end

    test "returns typed unsupported-capability errors before execution" do
      request = Request.new(operation: :embedding, backend: :text_backend)
      capabilities = Capabilities.new(text_generation: true)

      assert {:error, %Error.Backend.UnsupportedCapability{} = error} =
               Capabilities.validate_request(capabilities, request, backend: :text_backend)

      assert error.backend == :text_backend
      assert error.capability == :embeddings
      assert error.operation == :embedding
    end
  end

  describe "backend behaviour helpers" do
    test "validates backend request capabilities through the behaviour helper" do
      request =
        Request.new(
          backend: :text_backend,
          stream?: true,
          messages: [%{role: :user, content: "hello"}]
        )

      assert {:error, %Error.Backend.UnsupportedCapability{} = error} =
               Backend.validate_request(TextBackend, request)

      assert error.backend == :text_backend
      assert error.capability == :streaming
    end

    test "returns unsupported-backend for modules without backend callbacks" do
      request = Request.new(prompt: "hello")

      assert {:error, %Error.Backend.UnsupportedBackend{} = error} =
               Backend.validate_request(__MODULE__, request)

      assert error.backend == __MODULE__
    end

    test "supports?/2 reads backend capability flags" do
      assert Backend.supports?(TextBackend, :text_generation)
      refute Backend.supports?(TextBackend, :embeddings)
    end
  end

  describe "result and event modeling" do
    test "normalizes backend result and event envelopes" do
      result =
        Result.new(
          backend: :req_llm,
          operation: :text,
          text: "done",
          usage: %{total_tokens: 3},
          model: "anthropic:claude-haiku-4-5"
        )

      event =
        Event.new(
          backend: :req_llm,
          request_id: "req_1",
          operation: :text,
          kind: :completed,
          data: %{result: result}
        )

      assert result.text == "done"
      assert result.usage == %{total_tokens: 3}
      assert event.kind == :completed
      assert event.data.result == result
      assert event.request_id == "req_1"
    end
  end
end
