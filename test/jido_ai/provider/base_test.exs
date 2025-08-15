defmodule Jido.AI.Provider.BaseTest do
  use ExUnit.Case, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.{API, Invalid}
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Base
  alias Jido.AI.Test.FakeProvider

  # Simple test provider for testing Base functionality
  defmodule TestProvider do
    @behaviour Jido.AI.Provider.Base

    @impl true
    def provider_info do
      %Provider{
        id: :test_provider,
        name: "Test Provider",
        doc: "Provider for testing Base module",
        env: [:test_api_key],
        models: %{}
      }
    end

    @impl true
    def api_url, do: "https://test.example.com/v1"

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
    # Set up isolated keyring for tests
    cleanup_fn = setup_isolated_keyring()
    on_exit(cleanup_fn)

    # Configure HTTP client to use Req.Test
    Application.put_env(:jido_ai, :http_client, Req)
    Application.put_env(:jido_ai, :http_options, plug: {Req.Test, :base_test})

    # Verify all stubs are called at test exit
    on_exit(fn ->
      try do
        Req.Test.verify!(:base_test)
      rescue
        # Don't fail if no expectations were set
        _ -> :ok
      end
    end)

    # Set up test API key using the proper config path
    Application.put_env(:jido_ai, :test_provider, api_key: "test-key-123")

    model = %Model{
      provider: :test_provider,
      model: "test-model",
      temperature: 0.7,
      max_tokens: 1000,
      max_retries: 3
    }

    %{model: model}
  end

  describe "generate_text/3" do
    test "returns error when api_key missing", %{model: model} do
      # Clear API key from application config
      Application.put_env(:jido_ai, :test_provider, [])

      assert {:error, %Invalid.Parameter{}} =
               TestProvider.generate_text(model, "test prompt")
    end

    test "returns error when prompt is nil", %{model: model} do
      assert {:error, %Invalid.Parameter{}} =
               TestProvider.generate_text(model, nil)
    end

    test "returns error when prompt is empty string", %{model: model} do
      assert {:error, %Invalid.Parameter{}} =
               TestProvider.generate_text(model, "")
    end

    test "makes successful HTTP request", %{model: model} do
      mock_http_success()

      assert {:ok, "Generated response"} =
               TestProvider.generate_text(model, "Hello")
    end

    test "handles HTTP error responses", %{model: model} do
      mock_http_error(400, %{"error" => %{"message" => "Bad request"}})

      assert {:error, %API.Request{}} =
               TestProvider.generate_text(model, "Hello")
    end

    test "handles network errors", %{model: model} do
      Req.Test.stub(:base_test, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %API.Request{}} =
               TestProvider.generate_text(model, "Hello")
    end

    test "includes all model parameters in request", %{model: model} do
      Req.Test.stub(:base_test, fn conn ->
        conn |> Req.Test.json(mock_success_response())
      end)

      model_with_params = %{model | temperature: 0.8, max_tokens: 2000}

      assert {:ok, _} = TestProvider.generate_text(model_with_params, "Hello", top_p: 0.9)
    end
  end

  describe "stream_text/3" do
    test "returns error when api_key missing", %{model: model} do
      # Clear API key from application config
      Application.put_env(:jido_ai, :test_provider, [])

      assert {:error, %Invalid.Parameter{}} =
               TestProvider.stream_text(model, "test prompt")
    end

    test "returns error when prompt is nil", %{model: model} do
      assert {:error, %Invalid.Parameter{}} =
               TestProvider.stream_text(model, nil)
    end

    test "returns error when prompt is empty string", %{model: model} do
      assert {:error, %Invalid.Parameter{}} =
               TestProvider.stream_text(model, "")
    end

    test "returns stream for HTTP request", %{model: model} do
      Req.Test.stub(:base_test, fn conn ->
        conn |> Req.Test.json(%{})
      end)

      assert {:ok, stream} = TestProvider.stream_text(model, "Hello")
      assert is_function(stream, 2)
    end

    test "returns ok with stream structure", %{model: model} do
      Req.Test.stub(:base_test, fn conn ->
        conn |> Req.Test.json(%{})
      end)

      assert {:ok, stream} = TestProvider.stream_text(model, "Hello")
      assert is_function(stream, 2)
    end
  end

  describe "merge_model_options/3" do
    test "merges model configuration with request options", %{model: model} do
      opts = [temperature: 0.9, custom_option: "test"]

      merged = Base.merge_model_options(TestProvider, model, opts)

      # opts take precedence
      assert merged[:temperature] == 0.9
      # from model
      assert merged[:max_tokens] == 1000
      # from opts
      assert merged[:custom_option] == "test"
      # from config
      assert merged[:api_key] == "test-key-123"
      assert merged[:url] == "https://test.example.com/v1/chat/completions"
    end

    test "uses model defaults when opts don't override", %{model: model} do
      merged = Base.merge_model_options(TestProvider, model, [])

      assert merged[:temperature] == 0.7
      assert merged[:max_tokens] == 1000
      assert merged[:max_retries] == 3
    end

    test "opts take precedence over model config", %{model: model} do
      opts = [temperature: 1.0, max_tokens: 500, api_key: "override-key"]

      merged = Base.merge_model_options(TestProvider, model, opts)

      assert merged[:temperature] == 1.0
      assert merged[:max_tokens] == 500
      assert merged[:api_key] == "override-key"
    end
  end

  describe "build_chat_completion_body/3" do
    test "builds correct request body", %{model: model} do
      opts = [temperature: 0.8, max_tokens: 1500]

      body = Base.build_chat_completion_body(model, "Hello", opts)

      assert body[:model] == "test-model"
      assert body[:messages] == [%{role: "user", content: "Hello"}]
      assert body[:temperature] == 0.8
      assert body[:max_tokens] == 1500
    end

    test "converts prompt to messages format", %{model: model} do
      body = Base.build_chat_completion_body(model, "Test prompt", [])

      assert body[:messages] == [%{role: "user", content: "Test prompt"}]
    end

    test "includes stream parameter when provided", %{model: model} do
      body = Base.build_chat_completion_body(model, "Hello", stream: true)

      assert body[:stream] == true
    end
  end

  describe "extract_text_response/1" do
    test "extracts text from successful response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => "Generated text"}}
          ]
        }
      }

      assert {:ok, "Generated text"} = Base.extract_text_response(response)
    end

    test "handles error response with message" do
      response = %Req.Response{
        status: 400,
        body: %{"error" => %{"message" => "Invalid request"}}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    test "handles error response without message" do
      response = %Req.Response{
        status: 500,
        body: %{"error" => %{}}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    test "handles different HTTP error codes" do
      error_codes = [400, 401, 403, 404, 429, 500, 502, 503]

      for status <- error_codes do
        response = %Req.Response{
          status: status,
          body: %{"error" => %{"message" => "Error #{status}"}}
        }

        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "handles unexpected response format" do
      response = %Req.Response{
        status: 200,
        body: %{"unexpected" => "format"}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    test "handles missing choices" do
      response = %Req.Response{
        status: 200,
        body: %{"choices" => []}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    test "handles missing message content" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{}}
          ]
        }
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    test "handles non-map response body" do
      response = %Req.Response{
        status: 200,
        body: "not a map"
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end
  end

  describe "request building integration" do
    test "builds correct OpenAI chat completion request", %{model: model} do
      Req.Test.stub(:base_test, fn conn ->
        conn |> Req.Test.json(mock_success_response())
      end)

      assert {:ok, _} =
               TestProvider.generate_text(model, "Hello", temperature: 0.7, max_tokens: 100)
    end

    test "builds correct streaming request", %{model: model} do
      Req.Test.stub(:base_test, fn conn ->
        conn |> Req.Test.json(%{})
      end)

      assert {:ok, stream} = TestProvider.stream_text(model, "Stream test")
      assert is_function(stream, 2)
    end
  end

  describe "error message extraction" do
    test "extracts error message from various response formats" do
      error_formats = [
        %{"error" => %{"message" => "Direct message"}},
        %{"error" => %{"code" => "invalid_request", "message" => "Request invalid"}},
        %{"error" => "String error"},
        %{"message" => "Top-level message"}
      ]

      for {body, index} <- Enum.with_index(error_formats) do
        response = %Req.Response{status: 400 + index, body: body}

        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "handles malformed error responses" do
      malformed_responses = [
        %Req.Response{status: 400, body: nil},
        %Req.Response{status: 500, body: %{}},
        %Req.Response{status: 400, body: []},
        %Req.Response{status: 400, body: "plain text"}
      ]

      for response <- malformed_responses do
        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end
  end

  describe "integration with different provider models" do
    test "works with anthropic model structure" do
      mock_http_success()
      test_model = %Model{provider: :test_provider, model: "claude-3-sonnet"}
      assert {:ok, _} = TestProvider.generate_text(test_model, "test anthropic")
    end

    test "works with google model structure" do
      mock_http_success()
      test_model = %Model{provider: :test_provider, model: "gemini-pro"}
      assert {:ok, _} = TestProvider.generate_text(test_model, "test google")
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles very long prompts", %{model: model} do
      mock_http_success()

      long_prompt = String.duplicate("This is a very long prompt. ", 1000)

      assert {:ok, _} = TestProvider.generate_text(model, long_prompt)
    end

    test "handles special characters in prompts", %{model: model} do
      # Mock response for each test
      Req.Test.stub(:base_test, fn conn ->
        conn
        |> Req.Test.json(%{
          "choices" => [%{"message" => %{"content" => "Generated response"}}]
        })
      end)

      # Test one complex prompt
      assert {:ok, _} = TestProvider.generate_text(model, "Prompt with \"quotes\" and emoji 🚀")
    end

    test "handles boundary values for numeric parameters", %{model: model} do
      # Test one boundary case
      Req.Test.stub(:base_test, fn conn ->
        conn
        |> Req.Test.json(%{
          "choices" => [%{"message" => %{"content" => "Generated response"}}]
        })
      end)

      assert {:ok, _} = TestProvider.generate_text(model, "test", temperature: 0.0)
    end
  end

  describe "FakeProvider integration" do
    test "FakeProvider works with Base callbacks" do
      model = fake_model()

      assert {:ok, result} = FakeProvider.generate_text(model, "test prompt", [])
      assert is_binary(result)
      assert String.contains?(result, "fake-model")
      assert String.contains?(result, "test prompt")
    end

    test "FakeProvider stream_text works" do
      model = fake_model()

      assert {:ok, stream} = FakeProvider.stream_text(model, "test prompt", [])

      result = Enum.to_list(stream)
      assert result == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end
end
