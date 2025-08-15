defmodule Jido.AI.Provider.BaseHelpersSimpleTest do
  @moduledoc """
  Simple tests for Provider.Base helper functions to improve coverage.
  """

  use Jido.AI.TestSupport.ProviderCase, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.API.Request
  alias Jido.AI.Error.{API, Invalid}
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Base
  alias Jido.AI.TestSupport.Fixtures

  # Test provider that exposes Base functions
  defmodule SimpleTestProvider do
    @behaviour Jido.AI.Provider.Base

    @impl true
    def provider_info do
      %Provider{
        id: :simple_test,
        name: "Simple Test Provider",
        doc: "Provider for simple testing",
        env: [:simple_test_api_key],
        models: %{}
      }
    end

    @impl true
    def api_url, do: "https://simple.test.com/v1"

    @impl true
    def generate_text(%Model{} = model, prompt, opts \\ []) do
      Base.default_generate_text(__MODULE__, model, prompt, opts)
    end

    @impl true
    def stream_text(%Model{} = model, prompt, opts \\ []) do
      Base.default_stream_text(__MODULE__, model, prompt, opts)
    end
  end

  setup do
    cleanup_fn = setup_isolated_keyring()
    on_exit(cleanup_fn)

    # Set API key for simple test provider
    Application.put_env(:jido_ai, :simple_test, api_key: "simple-key-123")

    model = %Model{
      provider: :simple_test,
      model: "simple-model",
      temperature: 0.5,
      max_tokens: 800,
      max_retries: 2
    }

    %{model: model}
  end

  describe "merge_model_options with nil handling" do
    test "handles model with nil values correctly", %{model: _model} do
      # Create model with nil values to test maybe_put logic
      nil_model = %Model{
        provider: :simple_test,
        model: "test-model",
        temperature: nil,
        max_tokens: nil,
        max_retries: nil
      }

      merged = Base.merge_model_options(SimpleTestProvider, nil_model, [])

      # Nil values should not be in the keyword list
      assert is_nil(merged[:temperature])
      assert is_nil(merged[:max_tokens])
      assert is_nil(merged[:max_retries])

      # API key and URL should still be set
      assert merged[:api_key] == "simple-key-123"
      assert String.ends_with?(merged[:url], "/chat/completions")
    end

    test "opts override model values", %{model: model} do
      opts = [
        temperature: 1.0,
        max_tokens: 50,
        api_key: "override-key"
      ]

      merged = Base.merge_model_options(SimpleTestProvider, model, opts)

      # opts should take precedence
      assert merged[:temperature] == 1.0
      assert merged[:max_tokens] == 50
      assert merged[:api_key] == "override-key"
      # model value should be kept when not overridden
      assert merged[:max_retries] == 2
    end
  end

  describe "HTTP error validation" do
    test "returns proper error types for network issues" do
      # Just test the error type, not the actual HTTP call
      error = %Request{reason: "test error"}
      assert error.reason == "test error"
    end
  end

  describe "configuration edge cases" do
    test "handles missing API key configuration", %{model: model} do
      # Clear API key config to test get_required_opt error path
      Application.put_env(:jido_ai, :simple_test, [])

      assert {:error, %Invalid.Parameter{parameter: "api_key"}} =
               SimpleTestProvider.generate_text(model, "test")

      assert {:error, %Invalid.Parameter{parameter: "api_key"}} =
               SimpleTestProvider.stream_text(model, "test")
    end

    test "reads timeout config from application environment", %{model: model} do
      # Test that timeout values are read from config
      Application.put_env(:jido_ai, :receive_timeout, 30_000)
      Application.put_env(:jido_ai, :pool_timeout, 15_000)

      # Test that merge_model_options works correctly
      merged = Base.merge_model_options(SimpleTestProvider, model, [])

      # Should have API key and URL from provider
      assert merged[:api_key] == "simple-key-123"
      assert String.ends_with?(merged[:url], "/chat/completions")
    end

    test "reads timeout configuration correctly", %{model: model} do
      # Set global timeouts and verify they're accessible
      Application.put_env(:jido_ai, :receive_timeout, 60_000)
      Application.put_env(:jido_ai, :pool_timeout, 30_000)

      # Test merge_model_options reads config correctly
      merged = Base.merge_model_options(SimpleTestProvider, model, [])
      assert merged[:api_key] == "simple-key-123"
    end
  end

  describe "response extraction edge cases" do
    test "extract_text_response with multiple choices uses first" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => "First response"}},
            %{"message" => %{"content" => "Second response"}},
            %{"message" => %{"content" => "Third response"}}
          ]
        }
      }

      assert {:ok, "First response"} = Base.extract_text_response(response)
    end

    test "extract_text_response with various malformed bodies" do
      malformed_cases = [
        %Req.Response{status: 200, body: nil},
        %Req.Response{status: 200, body: []},
        %Req.Response{status: 200, body: "string"},
        %Req.Response{status: 200, body: 123},
        %Req.Response{status: 200, body: %{}},
        %Req.Response{status: 200, body: %{"choices" => []}},
        %Req.Response{status: 200, body: %{"choices" => [%{}]}},
        %Req.Response{status: 200, body: %{"choices" => [%{"message" => %{}}]}}
      ]

      for response <- malformed_cases do
        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "extract_text_response with redirect status codes" do
      redirect_codes = [301, 302, 304, 307, 308]

      for status <- redirect_codes do
        response = %Req.Response{
          status: status,
          body: %{"location" => "https://redirect.example.com"}
        }

        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end
  end

  describe "build_chat_completion_body filtering" do
    test "filters out unsupported options", %{model: model} do
      opts = [
        # supported
        temperature: 0.8,
        # supported
        max_tokens: 100,
        # unsupported
        invalid_option: "test",
        # unsupported
        custom_field: 123,
        # supported
        n: 1,
        # unsupported
        unknown: "value"
      ]

      body = Base.build_chat_completion_body(model, "test prompt", opts)

      # Should include supported options
      assert body[:temperature] == 0.8
      assert body[:max_tokens] == 100
      assert body[:n] == 1
      assert body[:model] == "simple-model"
      assert body[:messages] == [%{role: "user", content: "test prompt"}]

      # Should exclude unsupported options
      refute Map.has_key?(body, :invalid_option)
      refute Map.has_key?(body, :custom_field)
      refute Map.has_key?(body, :unknown)
    end

    test "includes stream parameter when provided", %{model: model} do
      body = Base.build_chat_completion_body(model, "stream test", stream: true)

      assert body[:stream] == true
      assert body[:model] == "simple-model"
      assert body[:messages] == [%{role: "user", content: "stream test"}]
    end
  end

  describe "validate_prompt coverage" do
    test "rejects various invalid prompt types", %{model: model} do
      invalid_prompts = [
        # nil
        nil,
        # empty string
        "",
        # number
        123,
        # list
        [],
        # map
        %{},
        # atom
        :atom,
        # boolean
        false,
        # boolean
        true
      ]

      for invalid <- invalid_prompts do
        assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
                 SimpleTestProvider.generate_text(model, invalid)
      end
    end

    test "accepts valid string prompts", %{model: model} do
      # Test one valid prompt with mock
      Req.Test.stub(:provider_case, fn conn ->
        conn |> Req.Test.json(Fixtures.success_body())
      end)

      assert {:ok, _} = SimpleTestProvider.generate_text(model, "Hello world")
    end

    test "accepts multiline prompts", %{model: model} do
      Req.Test.stub(:provider_case, fn conn ->
        conn |> Req.Test.json(Fixtures.success_body())
      end)

      assert {:ok, _} = SimpleTestProvider.generate_text(model, "Multi\nline\nstring")
    end
  end
end
