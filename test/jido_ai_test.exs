defmodule Jido.AITest do
  use ExUnit.Case, async: true

  import Jido.AI.TestUtils
  import Mimic

  alias Jido.AI
  alias Jido.AI.Error.API.Request
  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.Test.FakeProvider

  doctest Jido.AI

  setup :verify_on_exit!

  setup do
    copy(Keyring)
    # Register providers for testing
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)
    Jido.AI.Provider.Registry.register(:openai, OpenAI)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "api_key/1" do
    test "returns nil when no key configured" do
      stub(Keyring, :get, fn _, _, _ -> nil end)
      assert AI.api_key(:openai_api_key) == nil
    end

    test "returns key when available (atom)" do
      stub(Keyring, :get, fn
        Keyring, :openai_api_key, nil -> "provider-key"
      end)

      assert AI.api_key(:openai_api_key) == "provider-key"
    end

    test "returns key when available (string)" do
      stub(Keyring, :get, fn
        "anthropic_api_key", nil -> "anthropic-key"
      end)

      assert AI.api_key("anthropic_api_key") == "anthropic-key"
    end

    test "handles case-insensitive string keys" do
      stub(Keyring, :get, fn
        "openai_api_key", nil -> "case-insensitive-key"
      end)

      assert AI.api_key("OPENAI_API_KEY") == "case-insensitive-key"
      assert AI.api_key("OpenAI_API_Key") == "case-insensitive-key"
    end
  end

  describe "provider/1" do
    test "returns provider module from registry" do
      assert {:ok, FakeProvider} = AI.provider(:fake)
    end

    test "returns error for unknown provider" do
      assert {:error, :not_found} = AI.provider(:unknown)
    end
  end

  describe "list_keys/0" do
    test "delegates to keyring" do
      stub(Keyring, :list, fn Keyring -> ["key1", "key2"] end)
      assert AI.list_keys() == ["key1", "key2"]
    end
  end

  describe "model/1" do
    test "accepts string format" do
      stub(Keyring, :get, fn _, _, default -> default end)

      assert {:ok, model} = AI.model("fake:fake-model")
      assert model.provider == :fake
      assert model.model == "fake-model"
    end

    test "accepts tuple format" do
      stub(Keyring, :get, fn _, _, default -> default end)

      assert {:ok, model} = AI.model({:fake, model: "fake-model", temperature: 0.8})
      assert model.provider == :fake
      assert model.model == "fake-model"
      assert model.temperature == 0.8
    end

    test "accepts struct format" do
      model_struct = openai_gpt4_model()
      assert {:ok, ^model_struct} = AI.model(model_struct)
    end

    test "handles Model struct directly in text generation" do
      stub(Keyring, :get, fn _, _, _ -> nil end)

      model_struct = %Model{
        provider: :fake,
        model: "test-model",
        temperature: 0.5
      }

      # This should hit the ensure_model_struct(%Model{} = model) clause
      {:ok, result} = AI.generate_text(model_struct, "hello")
      assert result =~ "test-model"
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
      stub(Keyring, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model", temperature: 0.3}

      {:ok, result} = AI.generate_text(model, "hello", max_tokens: 50)

      assert result =~ "fake-model"
      assert result =~ "hello"
      assert result =~ "temperature: 0.3"
      assert result =~ "max_tokens: 50"
    end

    test "propagates provider errors" do
      stub(Keyring, :get, fn _, _, _ -> nil end)

      defmodule ErrorProvider do
        def api_url, do: "https://error.test/v1"
        def generate_text(_, _, _), do: {:error, %Request{reason: "API Error"}}
        def provider_info, do: %{id: :error_provider, env: []}
      end

      Jido.AI.Provider.Registry.register(:error_provider, ErrorProvider)

      model = {:error_provider, model: "test"}
      assert {:error, %Request{}} = AI.generate_text(model, "hello")
    end

    test "handles invalid model spec" do
      assert {:error, "Invalid model specification. Expected format: 'provider:model'"} =
               AI.generate_text("invalid", "hello")
    end

    test "merges opts with model parameters" do
      stub(Keyring, :get, fn _, _, _ -> nil end)

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
      stub(Keyring, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model"}

      {:ok, stream} = AI.stream_text(model, "hello", temperature: 0.7)
      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "propagates provider stream errors" do
      stub(Keyring, :get, fn _, _, _ -> nil end)

      defmodule StreamErrorProvider do
        def api_url, do: "https://stream-error.test/v1"
        def stream_text(_, _, _), do: {:error, %Request{reason: "Stream Error"}}
        def provider_info, do: %{id: :stream_error, env: []}
      end

      Jido.AI.Provider.Registry.register(:stream_error, StreamErrorProvider)

      model = {:stream_error, model: "test"}
      assert {:error, %Request{}} = AI.stream_text(model, "hello")
    end

    test "handles invalid model spec in streaming" do
      assert {:error, "Invalid model specification. Expected format: 'provider:model'"} =
               AI.stream_text("invalid", "hello")
    end
  end

  describe "config/2" do
    test "handles nested config with non-api_key fallback" do
      # This should hit line 118 (default for non-api_key nested configs)
      result = AI.config([:openai, :some_other_key], "default_value")
      assert result == "default_value"
    end

    test "handles nested config in keyword list with non-api_key fallback" do
      # Set up application config with keyword list
      Application.put_env(:jido_ai, :openai, base_url: "https://api.openai.com")

      # This should hit line 136 (default for non-api_key in keyword list)
      result = AI.config([:openai, :some_other_key], "fallback_value")
      assert result == "fallback_value"

      # Clean up
      Application.delete_env(:jido_ai, :openai)
    end

    test "handles config with non-list main value" do
      # Set up application config with non-list value
      Application.put_env(:jido_ai, :test_key, "string_value")

      # This should hit line 142 (_main -> default)
      result = AI.config([:test_key, :nested], "default_val")
      assert result == "default_val"

      # Clean up
      Application.delete_env(:jido_ai, :test_key)
    end
  end

  describe "configuration integration" do
    test "uses keyring for api_key lookup" do
      stub(Keyring, :get, fn
        Keyring, :fake_api_key, nil -> "fake-secret"
        _, _, default -> default
      end)

      model = {:fake, model: "fake-model"}

      {:ok, result} = AI.generate_text(model, "hello")
      assert result =~ "api_key: \"fake-secret\""
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
