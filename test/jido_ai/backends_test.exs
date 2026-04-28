defmodule Jido.AI.BackendsTest do
  # covers: jido_ai.examples_and_quality.executable_contract_regression_tests
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.AI.Backends
  alias Jido.AI.Request
  alias Jido.AI.Error

  defmodule FakeRuntimeServer do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def last_signal(pid) do
      GenServer.call(pid, :last_signal)
    end

    @impl true
    def init(_opts), do: {:ok, %{last_signal: nil}}

    @impl true
    def handle_call(:last_signal, _from, state), do: {:reply, state.last_signal, state}

    @impl true
    def handle_cast({:signal, signal}, state), do: {:noreply, %{state | last_signal: signal}}
  end

  setup :set_mimic_from_context

  setup do
    old_backend = Application.get_env(:jido_ai, :llm_backend)
    old_backends = Application.get_env(:jido_ai, :llm_backends)

    on_exit(fn ->
      restore_env(:llm_backend, old_backend)
      restore_env(:llm_backends, old_backends)
    end)

    :ok
  end

  describe "backend config" do
    test "defaults to req_llm when no alternate backend is configured" do
      Application.delete_env(:jido_ai, :llm_backend)
      assert Backends.default_backend() == :req_llm
      assert Backends.request_backend([]) == :req_llm
    end

    test "merges additive backend config without replacing reserved backends" do
      Application.put_env(:jido_ai, :llm_backend, :req_llm)
      Application.put_env(:jido_ai, :llm_backends, %{req_llm: %{timeout_ms: 1_000}, harness: %{session_mode: :exec}})

      assert Backends.config_for(:req_llm).transport == :api
      assert Backends.config_for(:req_llm).timeout_ms == 1_000
      assert Backends.config_for(:harness).transport == :exec
      assert Backends.config_for(:harness).session_mode == :exec
    end

    test "request-scoped backend overrides stay additive and explicit" do
      Application.put_env(:jido_ai, :llm_backend, :req_llm)

      assert Backends.request_backend(backend: :harness) == :harness
      assert {:ok, :req_llm} = Backends.ensure_supported_backend([], [:req_llm])

      assert {:error, %Error.Backend.UnsupportedBackend{} = error} =
               Backends.ensure_supported_backend([backend: :harness], [:req_llm])

      assert error.backend == :harness
      assert error.supported_backends == [:req_llm]
    end
  end

  describe "public facade compatibility guards" do
    test "generate_text/2 returns unsupported-backend before ReqLLM is called" do
      Mimic.stub(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
        flunk("ReqLLM should not be called for an unsupported backend")
      end)

      assert {:error, %Error.Backend.UnsupportedBackend{} = error} =
               AI.generate_text("hello", backend: :harness)

      assert error.backend == :harness
    end
  end

  describe "request-scoped backend overrides" do
    test "create_and_send/3 includes the resolved backend in the signal payload" do
      {:ok, server} = FakeRuntimeServer.start_link()

      assert {:ok, _handle} =
               Request.create_and_send(server, "What is 2+2?",
                 signal_type: "ai.test.query",
                 source: "/ai/test",
                 backend: :req_llm
               )

      signal = FakeRuntimeServer.last_signal(server)
      assert signal.data.backend == :req_llm
      assert signal.data.query == "What is 2+2?"
    end

    test "create_and_send/3 fails fast for unsupported request backends" do
      {:ok, server} = FakeRuntimeServer.start_link()

      assert {:error, %Error.Backend.UnsupportedBackend{} = error} =
               Request.create_and_send(server, "What is 2+2?",
                 signal_type: "ai.test.query",
                 source: "/ai/test",
                 backend: :harness
               )

      assert error.backend == :harness
      assert FakeRuntimeServer.last_signal(server) == nil
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_ai, key)
  defp restore_env(key, value), do: Application.put_env(:jido_ai, key, value)
end
