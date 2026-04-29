defmodule Jido.AI.Backends.HarnessTest do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Backend.Request
  alias Jido.AI.Backend.Result
  alias Jido.AI.Backends
  alias Jido.AI.Backends.Harness, as: HarnessBackend
  alias Jido.AI.Error

  setup :set_mimic_from_context

  setup do
    old_backends = Application.get_env(:jido_ai, :llm_backends)

    Application.put_env(:jido_ai, :llm_backends, %{
      harness: %{
        provider: :codex,
        run_opts: [transport: :exec],
        request_defaults: %{
          allowed_tools: ["read"],
          metadata: %{"origin" => "defaults"}
        }
      }
    })

    on_exit(fn ->
      restore_env(:llm_backends, old_backends)
    end)

    :ok
  end

  describe "adapter lookup" do
    test "resolves the harness adapter for the reserved backend" do
      assert Backends.adapter_for(:harness) == HarnessBackend
    end
  end

  describe "generate/1" do
    test "translates canonical requests into harness run requests and normalized results" do
      expect(Jido.Harness, :capabilities, fn :codex ->
        {:ok, %Jido.Harness.Capabilities{cancellation?: true}}
      end)

      expect(Jido.Harness, :run_request, fn :codex, %Jido.Harness.RunRequest{} = run_request, opts ->
        assert run_request.prompt == "Investigate the failure"
        assert run_request.cwd == "/tmp/project"
        assert run_request.model == "claude-sonnet-4"
        assert run_request.max_turns == 3
        assert run_request.timeout_ms == 5_000
        assert run_request.system_prompt == "Stay focused"
        assert Enum.sort(run_request.allowed_tools) == ["read", "write"]
        assert run_request.attachments == ["/tmp/project/notes.md"]
        assert run_request.metadata["origin"] == "defaults"
        assert run_request.metadata["request_id"] == "req_harness_generate"
        assert run_request.metadata["run_id"] == "run_harness_generate"
        assert run_request.metadata["session_id"] == "resume_123"
        assert opts == [transport: :exec, mode: :safe]

        {:ok,
         [
           Jido.Harness.Event.new!(%{
             type: :session_started,
             provider: :codex,
             session_id: "sess_42",
             timestamp: "2026-04-29T12:00:00Z",
             payload: %{}
           }),
           Jido.Harness.Event.new!(%{
             type: :thinking,
             provider: :codex,
             session_id: "sess_42",
             payload: %{"delta" => "considering options"}
           }),
           Jido.Harness.Event.new!(%{
             type: :usage,
             provider: :codex,
             session_id: "sess_42",
             payload: %{"input_tokens" => 7, "output_tokens" => 9}
           }),
           Jido.Harness.Event.new!(%{
             type: :final,
             provider: :codex,
             session_id: "sess_42",
             payload: %{"text" => "Use the newer backend seam.", "finish_reason" => "completed"}
           })
         ]}
      end)

      request =
        Request.new(
          request_id: "req_harness_generate",
          backend: :harness,
          operation: :text,
          prompt: "Investigate the failure",
          system_prompt: "Stay focused",
          model: "claude-sonnet-4",
          timeout_ms: 5_000,
          workspace: %{
            cwd: "/tmp/project",
            session_id: "resume_123",
            attachments: [%{path: "/tmp/project/notes.md"}]
          },
          backend_metadata: %{
            provider: :codex,
            allowed_tools: ["write"],
            max_turns: 3,
            run_opts: [mode: :safe]
          },
          metadata: %{run_id: "run_harness_generate"}
        )

      assert {:ok, %Result{} = result} = HarnessBackend.generate(request)
      assert result.backend == :harness
      assert result.operation == :text
      assert result.text == "Use the newer backend seam."
      assert result.thinking_content == "considering options"
      assert result.finish_reason == "completed"
      assert result.usage == %{input_tokens: 7, output_tokens: 9, total_tokens: 16}
      assert result.message_metadata.provider == :codex
      assert result.message_metadata.session_id == "sess_42"
    end

    test "fails with a typed provider error when no harness provider is configured" do
      Application.put_env(:jido_ai, :llm_backends, %{harness: %{provider: nil}})

      request =
        Request.new(
          backend: :harness,
          operation: :text,
          prompt: "hello",
          workspace: %{cwd: "/tmp/project"}
        )

      assert {:error, %Error.Backend.ProviderUnavailable{} = error} = HarnessBackend.generate(request)
      assert error.backend == :harness
    end

    test "fails fast for message-history requests that harness cannot satisfy" do
      request =
        Request.new(
          backend: :harness,
          operation: :text,
          prompt: "hello",
          messages: [%{role: :user, content: "hello"}],
          workspace: %{cwd: "/tmp/project"}
        )

      assert {:error, %Error.Backend.UnsupportedCapability{} = error} = HarnessBackend.generate(request)
      assert error.backend == :harness
      assert error.capability == :message_history
      assert error.operation == :text
    end
  end

  describe "run_stream/2" do
    test "maps harness event streams into canonical backend events with cancellation metadata" do
      expect(Jido.Harness, :capabilities, fn :codex ->
        {:ok, %Jido.Harness.Capabilities{cancellation?: true}}
      end)

      expect(Jido.Harness, :run_request, fn :codex, %Jido.Harness.RunRequest{} = run_request, [transport: :exec] ->
        assert run_request.prompt == "Stream the update"

        {:ok,
         [
           Jido.Harness.Event.new!(%{
             type: :session_started,
             provider: :codex,
             session_id: "sess_stream",
             timestamp: "2026-04-29T12:01:00Z",
             payload: %{}
           }),
           Jido.Harness.Event.new!(%{
             type: :text_delta,
             provider: :codex,
             session_id: "sess_stream",
             payload: %{"delta" => "Hello "}
           }),
           Jido.Harness.Event.new!(%{
             type: :tool_call,
             provider: :codex,
             session_id: "sess_stream",
             payload: %{"id" => "tool_1", "name" => "read_file", "arguments" => %{"path" => "README.md"}}
           }),
           Jido.Harness.Event.new!(%{
             type: :usage,
             provider: :codex,
             session_id: "sess_stream",
             payload: %{"input_tokens" => 3, "output_tokens" => 4}
           }),
           Jido.Harness.Event.new!(%{
             type: :final,
             provider: :codex,
             session_id: "sess_stream",
             payload: %{"text" => "Hello world"}
           })
         ]}
      end)

      expect(Jido.Harness, :cancel, fn :codex, "sess_stream" -> :ok end)

      request =
        Request.new(
          request_id: "req_harness_stream",
          backend: :harness,
          operation: :text,
          prompt: "Stream the update",
          workspace: %{cwd: "/tmp/project"}
        )

      parent = self()

      assert {:ok, %Result{} = result} =
               HarnessBackend.run_stream(request, fn event -> send(parent, {:backend_event, event}) end)

      assert_receive {:backend_event, %Jido.AI.Backend.Event{kind: :started} = started}
      assert started.data.provider == :codex

      assert_receive {:backend_event, %Jido.AI.Backend.Event{kind: :metadata} = metadata_event}
      assert metadata_event.data.session_id == "sess_stream"
      assert is_function(metadata_event.data.control.cancel, 0)
      assert :ok = metadata_event.data.control.cancel.()

      assert_receive {:backend_event, %Jido.AI.Backend.Event{kind: :delta} = delta_event}
      assert delta_event.data.delta == "Hello "

      assert_receive {:backend_event, %Jido.AI.Backend.Event{kind: :tool_call} = tool_event}
      assert tool_event.data.name == "read_file"

      assert_receive {:backend_event, %Jido.AI.Backend.Event{kind: :usage} = usage_event}
      assert usage_event.data.usage.total_tokens == 7

      assert_receive {:backend_event, %Jido.AI.Backend.Event{kind: :completed} = completed_event}
      assert completed_event.data.result.text == "Hello world"

      assert result.text == "Hello world"
      assert result.tool_calls == [%{id: "tool_1", name: "read_file", arguments: %{"path" => "README.md"}}]
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_ai, key)
  defp restore_env(key, value), do: Application.put_env(:jido_ai, key, value)
end
