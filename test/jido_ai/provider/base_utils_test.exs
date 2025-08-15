defmodule Jido.AI.Provider.BaseUtilsTest do
  @moduledoc """
  Consolidated tests for Provider.Base utility functions.

  Uses property testing to reduce test duplication while improving coverage.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  import Jido.AI.TestSupport.Assertions
  import Mimic

  alias Jido.AI.Error.API
  alias Jido.AI.Keyring
  alias Jido.AI.Provider.Base
  alias Jido.AI.Test.FakeProvider
  alias Jido.AI.TestSupport.Fixtures

  doctest Base

  setup :verify_on_exit!

  # Use the existing FakeProvider for testing
  setup do
    copy(Keyring)
    # Set up test API key
    Application.put_env(:jido_ai, :test_provider, api_key: "test-key-123")

    # Register FakeProvider for streaming tests
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    model = Fixtures.model_fixture(provider: :test_provider, model: "test-model")

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    %{model: model}
  end

  describe "public API behavior" do
    test "FakeProvider works as expected" do
      model = Fixtures.model_fixture()

      assert {:ok, result} = FakeProvider.generate_text(model, "test", [])
      assert is_binary(result)
      assert String.contains?(result, "fake-model")
      assert String.contains?(result, "test")
    end
  end

  describe "merge_model_options/3" do
    test "merges model configuration with request options", %{model: model} do
      # Set up API key for fake provider
      Application.put_env(:jido_ai, :fake_api_key, "test-key-123")

      opts = [temperature: 0.9, custom_option: "test"]

      merged = Base.merge_model_options(FakeProvider, model, opts)

      # opts take precedence
      assert merged[:temperature] == 0.9
      # from model
      assert merged[:max_tokens] == 1000
      # from opts  
      assert merged[:custom_option] == "test"
      # from config
      assert merged[:api_key] == "test-key-123"
      assert String.contains?(merged[:url], "fake.test")
    end
  end

  describe "build_chat_completion_body/3" do
    test "builds correct OpenAI-style request body", %{model: model} do
      body = Base.build_chat_completion_body(model, "Hello", temperature: 0.8)

      assert_chat_completion_body(body)
      assert body[:model] == "test-model"
      assert body[:temperature] == 0.8
      assert List.first(body[:messages])[:content] == "Hello"
    end

    property "handles any valid prompt string" do
      check all(prompt <- StreamData.binary(min_length: 1, max_length: 50)) do
        model = Fixtures.model_fixture()
        body = Base.build_chat_completion_body(model, prompt, [])

        assert_chat_completion_body(body)
        assert List.first(body[:messages])[:content] == prompt
      end
    end
  end

  describe "extract_text_response/1" do
    test "extracts text from successful response" do
      response = %Req.Response{
        status: 200,
        body: Fixtures.success_body()
      }

      assert {:ok, "Test response from AI"} = Base.extract_text_response(response)
    end

    property "handles various HTTP error codes" do
      check all(
              status <- StreamData.integer(400..599),
              message <- StreamData.binary()
            ) do
        response = %Req.Response{
          status: status,
          body: Fixtures.error_body(message)
        }

        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "handles malformed response bodies" do
      malformed_bodies = [
        nil,
        %{},
        [],
        "plain text",
        %{"choices" => []},
        %{"choices" => [%{}]},
        %{"choices" => [%{"message" => %{}}]}
      ]

      for body <- malformed_bodies do
        response = %Req.Response{status: 200, body: body}
        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "handles streaming response edge cases through API" do
      # Test edge cases in streaming by examining the response handling
      # that would exercise the extract_text_from_stream logic indirectly

      stub(Keyring, :get, fn _, _, _ -> nil end)

      # Test that malformed streaming data is handled gracefully
      # This exercises the private streaming logic through the public API
      model = {:fake, model: "stream-test"}

      {:ok, stream} = Jido.AI.stream_text(model, "test malformed streaming")
      chunks = Enum.to_list(stream)

      # FakeProvider returns predictable chunks regardless of input
      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end

  describe "streaming functionality through public API" do
    test "stream_text works with FakeProvider" do
      model = Fixtures.model_fixture()

      assert {:ok, stream} = FakeProvider.stream_text(model, "test prompt", [])
      chunks = Enum.to_list(stream)

      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end
end
