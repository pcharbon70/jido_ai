defmodule Jido.AI.Provider.BaseTest do
  use ExUnit.Case, async: true
  import Mimic
  import JidoAI.TestUtils

  alias Jido.AI.Provider.Base

  setup do
    copy(Jido.AI.Config)
    copy(Jido.AI.Keyring)
    :ok
  end

  setup :verify_on_exit!

  describe "generate_text_request/1" do
    test "returns error when api_key missing" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)

      opts = [model: "gpt-4", prompt: "test", api_key: nil]

      assert {:error, %Jido.AI.Error.Invalid.Parameter{}} =
               Base.generate_text_request(opts)
    end

    test "returns error when prompt missing" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)

      opts = [model: "gpt-4", api_key: "test-key", prompt: nil]

      assert {:error, %Jido.AI.Error.Invalid.Parameter{}} =
               Base.generate_text_request(opts)
    end

    test "makes successful HTTP request" do
      mock_http_success()

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello", temperature: 0.7,
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, "Generated response"} = Base.generate_text_request(opts)
    end

    test "handles HTTP error responses" do
      mock_http_error(400, %{"error" => %{"message" => "Bad request"}})

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello",
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.generate_text_request(opts)
    end

    test "handles network errors" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)
      stub(Req, :post, fn _, _ -> {:error, %Req.TransportError{reason: :timeout}} end)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello",
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.generate_text_request(opts)
    end

    test "includes all model parameters in request" do
      mock_req = fn _url, request_opts ->
        # Verify the request structure
        assert request_opts[:json][:model] == "gpt-4"
        assert request_opts[:json][:temperature] == 0.8
        assert request_opts[:json][:max_tokens] == 1000
        assert request_opts[:json][:top_p] == 0.9

        mock_success_response()
      end

      stub(Jido.AI.Config, :get_http_client, fn -> Req end)
      stub(Req, :post, mock_req)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello", temperature: 0.8, 
              max_tokens: 1000, top_p: 0.9, url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, _} = Base.generate_text_request(opts)
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

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
    end

    test "handles error response without message" do
      response = %Req.Response{
        status: 500,
        body: %{"error" => %{}}
      }

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
    end

    test "handles different HTTP error codes" do
      error_codes = [400, 401, 403, 404, 429, 500, 502, 503]

      for status <- error_codes do
        response = %Req.Response{
          status: status,
          body: %{"error" => %{"message" => "Error #{status}"}}
        }

        assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "handles unexpected response format" do
      response = %Req.Response{
        status: 200,
        body: %{"unexpected" => "format"}
      }

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
    end

    test "handles missing choices" do
      response = %Req.Response{
        status: 200,
        body: %{"choices" => []}
      }

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
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

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
    end

    test "handles non-map response body" do
      response = %Req.Response{
        status: 200,
        body: "not a map"
      }

      assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
    end
  end

  describe "stream_text_request/1" do
    test "returns error when api_key missing" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)

      opts = [model: "gpt-4", prompt: "test", api_key: nil]

      assert {:error, %Jido.AI.Error.Invalid.Parameter{}} =
               Base.stream_text_request(opts)
    end

    test "returns error when prompt missing" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)

      opts = [model: "gpt-4", api_key: "test-key", prompt: nil]

      assert {:error, %Jido.AI.Error.Invalid.Parameter{}} =
               Base.stream_text_request(opts)
    end

    test "returns error when url missing" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello"]

      assert {:error, %Jido.AI.Error.Invalid.Parameter{}} =
               Base.stream_text_request(opts)
    end

    test "returns error when model missing" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)

      opts = [api_key: "test-key", prompt: "Hello", url: "https://api.openai.com/v1/chat/completions"]

      assert {:error, %Jido.AI.Error.Invalid.Parameter{}} =
               Base.stream_text_request(opts)
    end

    test "returns stream for HTTP request" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)
      stub(Req, :post, fn _, _ -> {:ok, %Req.Response{status: 200, body: %{}}} end)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello",
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, stream} = Base.stream_text_request(opts)
      assert is_function(stream, 2)
    end

    test "returns ok with stream structure" do
      stub(Jido.AI.Config, :get_http_client, fn -> Req end)
      stub(Req, :post, fn _, _ -> {:ok, %Req.Response{status: 200, body: %{}}} end)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello",
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, stream} = Base.stream_text_request(opts)
      assert is_function(stream, 2)
    end
  end



  describe "request building integration" do
    test "builds correct OpenAI chat completion request" do
      mock_req = fn _url, request_opts ->
        json = request_opts[:json]

        # Verify request structure
        assert json[:model] == "gpt-4"
        assert json[:messages] == [%{role: "user", content: "Hello"}]
        assert json[:temperature] == 0.7
        assert json[:max_tokens] == 100

        mock_success_response()
      end

      stub(Jido.AI.Config, :get_http_client, fn -> Req end)
      stub(Req, :post, mock_req)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Hello", temperature: 0.7, 
              max_tokens: 100, url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, _} = Base.generate_text_request(opts)
    end

    test "builds correct streaming request" do
      mock_req = fn _url, request_opts ->
        json = request_opts[:json]

        # Verify streaming flag is set
        assert json[:stream] == true
        assert json[:model] == "gpt-4"
        assert json[:messages] == [%{role: "user", content: "Stream test"}]

        {:ok, %Req.Response{status: 200, body: %{}}}
      end

      stub(Jido.AI.Config, :get_http_client, fn -> Req end)
      stub(Req, :post, mock_req)

      opts = [model: "gpt-4", api_key: "test-key", prompt: "Stream test",
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, stream} = Base.stream_text_request(opts)
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

        assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
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
        assert {:error, %Jido.AI.Error.API.Request{}} = Base.extract_text_response(response)
      end
    end
  end



  describe "integration with provider models" do
    test "works with different provider model structures" do
      providers_and_models = [
        {"claude-3-sonnet", "test anthropic"},
        {"gemini-pro", "test google"},
        {"mistral-large", "test mistral"}
      ]

      for {model, prompt} <- providers_and_models do
        mock_http_success()

        opts = [api_key: "test-key", prompt: prompt, model: model,
                url: "https://api.openai.com/v1/chat/completions"]

        # Should not error on different model structures
        assert {:ok, _} = Base.generate_text_request(opts)
      end
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles very long prompts" do
      mock_http_success()

      long_prompt = String.duplicate("This is a very long prompt. ", 1000)
      opts = [api_key: "test-key", prompt: long_prompt, model: "gpt-4",
              url: "https://api.openai.com/v1/chat/completions"]

      assert {:ok, _} = Base.generate_text_request(opts)
    end

    test "handles special characters in prompts" do
      mock_http_success()

      special_prompts = [
        "Prompt with \"quotes\" and 'apostrophes'",
        "Prompt with\nnewlines\nand\ttabs",
        "Prompt with emoji 🚀🎉✨",
        "Prompt with unicode: αβγδε",
        "Prompt with JSON: {\"key\": \"value\"}"
      ]

      for prompt <- special_prompts do
        opts = [api_key: "test-key", prompt: prompt, model: "gpt-4",
                url: "https://api.openai.com/v1/chat/completions"]
        assert {:ok, _} = Base.generate_text_request(opts)
      end
    end

    test "handles boundary values for numeric parameters" do
      mock_http_success()

      boundary_cases = [
        [temperature: 0.0],
        [temperature: 2.0],
        [max_tokens: 1]
      ]

      for params <- boundary_cases do
        opts = [api_key: "test-key", prompt: "test", model: "gpt-4",
                url: "https://api.openai.com/v1/chat/completions"] ++ params

        assert {:ok, _} = Base.generate_text_request(opts)
      end
    end
  end
end
