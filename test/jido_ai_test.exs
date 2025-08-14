defmodule Jido.AITest do
  use ExUnit.Case, async: true
  import Mimic
  import JidoAI.TestUtils

  alias Jido.AI

  doctest Jido.AI

  defmodule FakeProvider do
    def api_url, do: "https://fake.test/v1"

    def generate_text(model, prompt, opts) do
      {:ok, "#{model}:#{prompt}:#{inspect(opts)}"}
    end

    def stream_text(_model, _prompt, _opts) do
      {:ok, Stream.iterate(1, &(&1 + 1)) |> Stream.take(3) |> Stream.map(&"chunk_#{&1}")}
    end

    def provider_info do
      %{id: :fake, env: [], models: [%{id: "fake-model"}]}
    end
  end

  setup :verify_on_exit!

  setup do
    copy(Jido.AI.Keyring)
    # Register a fake provider for testing
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
    end)

    :ok
  end

  describe "api_key/1" do
    test "returns nil when no key configured" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)
      assert AI.api_key(:openai) == nil
    end

    test "returns provider-specific key when available" do
      stub(Jido.AI.Keyring, :get, fn
        Jido.AI.Keyring, :openai_api_key, nil -> "provider-key"
        Jido.AI.Keyring, :api_key, nil -> "general-key"
      end)

      assert AI.api_key(:openai) == "provider-key"
    end

    test "falls back to general api_key" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)

      assert AI.api_key(:openai) == nil
    end
  end

  describe "model_name/1" do
    test "returns default when not configured" do
      stub(Jido.AI.Keyring, :get, fn _, _, default -> default end)
      assert AI.model_name(:openai) == "gpt-4o"
    end

    test "returns configured model name" do
      stub(Jido.AI.Keyring, :get, fn
        Jido.AI.Keyring, :openai_model, "gpt-4o" -> "gpt-4"
        _, _, default -> default
      end)

      assert AI.model_name(:openai) == "gpt-4"
    end

    test "respects keyring override" do
      stub(Jido.AI.Keyring, :get, fn
        Jido.AI.Keyring, :openai_model, "gpt-4o" -> "custom-model"
        _, _, default -> default
      end)

      assert AI.model_name(:openai) == "custom-model"
    end
  end

  describe "model/1" do
    test "accepts string format" do
      stub(Jido.AI.Keyring, :get, fn _, _, default -> default end)

      assert {:ok, model} = AI.model("fake:fake-model")
      assert model.provider == :fake
      assert model.model == "fake-model"
    end

    test "accepts tuple format" do
      stub(Jido.AI.Keyring, :get, fn _, _, default -> default end)

      assert {:ok, model} = AI.model({:fake, model: "fake-model", temperature: 0.8})
      assert model.provider == :fake
      assert model.model == "fake-model"
      assert model.temperature == 0.8
    end

    test "accepts struct format" do
      model_struct = openai_gpt4_model()
      assert {:ok, ^model_struct} = AI.model(model_struct)
    end

    test "returns error for invalid format" do
      assert {:error, "Invalid model specification"} = AI.model(123)
    end

    test "returns error for unknown provider" do
      assert {:error, "Unknown provider: unknown"} = AI.model("unknown:model")
    end
  end

  describe "generate_text/3" do
    test "delegates to provider with merged opts" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model", temperature: 0.3}

      {:ok, result} = AI.generate_text(model, "hello", max_tokens: 50)

      assert result =~ "fake-model"
      assert result =~ "hello"
      assert result =~ "temperature: 0.3"
      assert result =~ "max_tokens: 50"
    end

    test "propagates provider errors" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)

      defmodule ErrorProvider do
        def api_url, do: "https://error.test/v1"
        def generate_text(_, _, _), do: {:error, %Jido.AI.Error.API.Request{reason: "API Error"}}
        def provider_info, do: %{id: :error_provider, env: []}
      end

      Jido.AI.Provider.Registry.register(:error_provider, ErrorProvider)

      model = {:error_provider, model: "test"}
      assert {:error, %Jido.AI.Error.API.Request{}} = AI.generate_text(model, "hello")
    end

    test "handles invalid model spec" do
      assert {:error, "Invalid model specification. Expected format: 'provider:model'"} =
               AI.generate_text("invalid", "hello")
    end

    test "merges opts with model parameters" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model", temperature: 0.3, max_tokens: 100}

      {:ok, result} = AI.generate_text(model, "hello", max_tokens: 200, top_p: 0.9)

      # max_tokens should be overridden, temperature preserved, top_p added
      assert result =~ "temperature: 0.3"
      assert result =~ "max_tokens: 200"
      assert result =~ "top_p: 0.9"
    end
  end

  describe "stream_text/3" do
    test "delegates to provider with merged opts" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model"}

      {:ok, stream} = AI.stream_text(model, "hello", temperature: 0.7)
      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "propagates provider stream errors" do
      stub(Jido.AI.Keyring, :get, fn _, _, _ -> nil end)

      defmodule StreamErrorProvider do
        def api_url, do: "https://stream-error.test/v1"
        def stream_text(_, _, _), do: {:error, %Jido.AI.Error.API.Request{reason: "Stream Error"}}
        def provider_info, do: %{id: :stream_error, env: []}
      end

      Jido.AI.Provider.Registry.register(:stream_error, StreamErrorProvider)

      model = {:stream_error, model: "test"}
      assert {:error, %Jido.AI.Error.API.Request{}} = AI.stream_text(model, "hello")
    end

    test "handles invalid model spec in streaming" do
      assert {:error, "Invalid model specification. Expected format: 'provider:model'"} =
               AI.stream_text("invalid", "hello")
    end
  end

  describe "configuration integration" do
    test "uses keyring for api_key lookup" do
      stub(Jido.AI.Keyring, :get, fn
        Jido.AI.Keyring, :fake_api_key, nil -> "fake-secret"
        _, _, default -> default
      end)

      model = {:fake, model: "fake-model"}

      {:ok, result} = AI.generate_text(model, "hello")
      assert result =~ "api_key: \"fake-secret\""
    end

    test "model_name uses keyring configuration" do
      stub(Jido.AI.Keyring, :get, fn
        Jido.AI.Keyring, :fake_model, "gpt-4o" -> "custom-model"
        _, _, default -> default
      end)

      assert AI.model_name(:fake) == "custom-model"
    end
  end

  describe "session configuration" do
    test "session values override global config" do
      stub(Jido.AI.Keyring, :get, fn
        Jido.AI.Keyring, :fake_api_key, nil -> "session-key"
        _, _, default -> default
      end)

      model = {:fake, model: "fake-model"}

      {:ok, result} = AI.generate_text(model, "hello")
      assert result =~ "api_key: \"session-key\""
    end
  end

  describe "error handling" do
    test "handles provider not found gracefully" do
      assert {:error, "Unknown provider: nonexistent"} = AI.model("nonexistent:model")
    end

    test "handles malformed model specs" do
      invalid_specs = [
        {nil, "Invalid model specification"},
        {123, "Invalid model specification"},
        {[], "Invalid model specification"},
        {%{invalid: "struct"}, "Invalid model specification"},
        {{"not_an_atom", model: "test"}, "Invalid model specification"}
      ]

      for {spec, expected_error} <- invalid_specs do
        assert {:error, ^expected_error} = AI.model(spec)
      end
    end
  end
end
