defmodule Jido.AI.TestUtils do
  @moduledoc """
  Test support utilities for the JidoAI package.

  Provides helpers for:
  - Isolated Keyring setup/teardown
  - Provider registry management
  - Common test fixtures
  - HTTP mocking helpers
  """

  import ExUnit.Assertions
  import Mimic

  ## Keyring Test Utilities

  @doc """
  Sets up an isolated keyring for testing.
  Clears any existing keys and returns a cleanup function.

  ## Examples

      setup do
        cleanup_fn = TestUtils.setup_isolated_keyring()
        on_exit(cleanup_fn)
        :ok
      end
  """
  def setup_isolated_keyring do
    # Clear any existing keys
    Jido.AI.Keyring.clear_all_session_values()

    # Return cleanup function
    fn -> Jido.AI.Keyring.clear_all_session_values() end
  end

  @doc """
  Sets up keyring with test API keys for common providers.
  """
  def setup_test_keyring do
    cleanup_fn = setup_isolated_keyring()

    # Add test keys via session values
    Jido.AI.Keyring.set_session_value(:openai_api_key, "test-openai-key")
    Jido.AI.Keyring.set_session_value(:anthropic_api_key, "test-anthropic-key")
    Jido.AI.Keyring.set_session_value(:google_api_key, "test-google-key")
    Jido.AI.Keyring.set_session_value(:mistral_api_key, "test-mistral-key")

    cleanup_fn
  end

  ## Provider Registry Management

  @doc """
  Clears the provider registry by removing persistent_term data.
  Use this to ensure clean state between tests.
  """
  def clear_provider_registry do
    # Clear all persistent terms related to providers
    :persistent_term.erase({Provider.Registry, :providers})
    :persistent_term.erase({Provider.Registry, :initialized})
  end

  @doc """
  Resets the provider registry to a clean state.
  Returns a cleanup function that can be called in on_exit.
  """
  def reset_provider_registry do
    # Store current state
    current_providers = :persistent_term.get({Provider.Registry, :providers}, %{})
    current_initialized = :persistent_term.get({Provider.Registry, :initialized}, false)

    # Clear registry
    clear_provider_registry()

    # Return cleanup function to restore state
    fn ->
      if current_initialized do
        :persistent_term.put({Provider.Registry, :providers}, current_providers)
        :persistent_term.put({Provider.Registry, :initialized}, current_initialized)
      end
    end
  end

  ## Test Fixtures

  @doc """
  Returns a test Jido.AI.Model struct for OpenAI GPT-4.
  """
  def openai_gpt4_model do
    %Jido.AI.Model{
      provider: :openai,
      model: "gpt-4",
      base_url: "https://api.openai.com/v1",
      api_key: nil,
      temperature: nil,
      max_tokens: nil,
      max_retries: nil,
      id: "gpt-4",
      name: "GPT-4",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2023-03",
      last_updated: "2024-01",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 128_000, output: 4096}
    }
  end

  @doc """
  Returns a test model configuration for OpenAI GPT-4 (legacy format).
  """
  def gpt4_model do
    %{
      provider: :openai,
      model: "gpt-4",
      api_key: "test-openai-key",
      temperature: 0.7,
      max_tokens: 1000
    }
  end

  @doc """
  Returns a test Jido.AI.Model struct for Anthropic Claude.
  """
  def anthropic_claude_model do
    %Jido.AI.Model{
      provider: :anthropic,
      model: "claude-3-sonnet",
      base_url: "https://api.anthropic.com/v1",
      api_key: nil,
      temperature: nil,
      max_tokens: nil,
      max_retries: nil,
      id: "claude-3-sonnet",
      name: "Claude 3 Sonnet",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-03",
      last_updated: "2024-03",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 200_000, output: 4096}
    }
  end

  @doc """
  Returns a test model configuration for Claude (legacy format).
  """
  def claude_model do
    %{
      provider: :anthropic,
      model: "claude-3-opus-20240229",
      api_key: "test-anthropic-key",
      temperature: 0.8,
      max_tokens: 1500
    }
  end

  @doc """
  Returns a test Jido.AI.Model struct for Google Gemini.
  """
  def google_gemini_model do
    %Jido.AI.Model{
      provider: :google,
      model: "gemini-pro",
      base_url: "https://generativelanguage.googleapis.com/v1",
      api_key: nil,
      temperature: nil,
      max_tokens: nil,
      max_retries: nil,
      id: "gemini-pro",
      name: "Gemini Pro",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2023-12",
      last_updated: "2024-01",
      modalities: %{input: [:text, :image], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 1_048_576, output: 8192}
    }
  end

  @doc """
  Returns a test model configuration for Gemini (legacy format).
  """
  def gemini_model do
    %{
      provider: :google,
      model: "gemini-pro",
      api_key: "test-google-key",
      temperature: 0.6,
      max_tokens: 2000
    }
  end

  @doc """
  Returns a test Jido.AI.Model struct for Mistral.
  """
  def mistral_large_model do
    %Jido.AI.Model{
      provider: :mistral,
      model: "mistral-large",
      base_url: "https://api.mistral.ai/v1",
      api_key: nil,
      temperature: nil,
      max_tokens: nil,
      max_retries: nil,
      id: "mistral-large",
      name: "Mistral Large",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-02",
      last_updated: "2024-02",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 128_000, output: 4096}
    }
  end

  @doc """
  Returns a test model configuration for Mistral (legacy format).
  """
  def mistral_model do
    %{
      provider: :mistral,
      model: "mistral-large",
      api_key: "test-mistral-key",
      temperature: 0.7,
      max_tokens: 1200
    }
  end

  @doc """
  Returns a test Jido.AI.Model struct for a fake provider (testing).
  """
  def fake_model do
    %Jido.AI.Model{
      provider: :fake,
      model: "fake-model",
      base_url: "https://api.fake.com/v1",
      api_key: nil,
      temperature: nil,
      max_tokens: nil,
      max_retries: nil,
      id: "fake-model",
      name: "Fake Model",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-01",
      last_updated: "2024-01",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 100_000, output: 4096}
    }
  end

  @doc """
  Returns a list of all test model configurations.
  """
  def all_test_models do
    [gpt4_model(), claude_model(), gemini_model(), mistral_model()]
  end

  @doc """
  Returns a test provider configuration.
  """
  def test_provider(name, opts \\ []) do
    base_config = %{
      name: name,
      module: Keyword.get(opts, :module, JidoAI.Provider.Test),
      api_key_name: to_string(name),
      base_url: Keyword.get(opts, :base_url, "https://api.#{name}.com"),
      headers: Keyword.get(opts, :headers, %{"Content-Type" => "application/json"}),
      models: Keyword.get(opts, :models, ["test-model-1", "test-model-2"])
    }

    Map.merge(base_config, Map.new(opts))
  end

  ## HTTP Mocking Helpers (using Req instead of HTTPoison)

  @doc """
  Sets up HTTP mocking using Mimic for Req requests.
  Returns a cleanup function.
  """
  def setup_http_mocking do
    Mimic.copy(Req)

    # Mimic automatically resets after each test
    fn -> :ok end
  end

  @doc """
  Mocks a successful HTTP request with default OpenAI response.
  """
  def mock_http_success do
    Application.put_env(:jido_ai, :http_client, Req)

    stub(Req, :post, fn _client, _opts ->
      mock_success_response()
    end)
  end

  @doc """
  Mocks a successful HTTP request with the given response.
  """
  def mock_http_success(url, response_body, opts \\ []) do
    status_code = Keyword.get(opts, :status_code, 200)
    headers = Keyword.get(opts, :headers, [{"content-type", "application/json"}])

    Req
    |> Mimic.expect(:post, fn ^url, _options ->
      {:ok,
       %Req.Response{
         status: status_code,
         body: response_body,
         headers: headers
       }}
    end)
  end

  @doc """
  Mocks an HTTP error response with status and body or transport error.
  """
  def mock_http_error(status_or_url, body_or_error_reason \\ :timeout)

  def mock_http_error(status, body) when is_integer(status) do
    Application.put_env(:jido_ai, :http_client, Req)

    stub(Req, :post, fn _client, _opts ->
      {:ok, %Req.Response{status: status, body: body}}
    end)
  end

  def mock_http_error(url, error_reason) when is_binary(url) do
    Req
    |> Mimic.expect(:post, fn ^url, _options ->
      {:error, %Req.TransportError{reason: error_reason}}
    end)
  end

  @doc """
  Mocks an HTTP response with a specific status code and error body.
  """
  def mock_http_error_response(url, status_code, error_body) do
    Req
    |> Mimic.expect(:post, fn ^url, _options ->
      {:ok,
       %Req.Response{
         status: status_code,
         body: error_body,
         headers: [{"content-type", "application/json"}]
       }}
    end)
  end

  @doc """
  Mocks SSE stream with the given chunks.
  """
  def mock_sse_stream(chunks) do
    Application.put_env(:jido_ai, :http_client, Req)

    stub(Req, :post, fn _client, _opts ->
      # Create a stream from the chunks
      stream = Stream.map(chunks, fn chunk -> chunk end)
      {:ok, %Req.Response{status: 200, body: stream}}
    end)
  end

  @doc """
  Mocks SSE response with content chunks.
  """
  def mock_sse_response(content_chunks) do
    chunks =
      Enum.map(content_chunks, fn content ->
        "data: {\"choices\":[{\"delta\":{\"content\":\"#{content}\"}}]}\n\n"
      end) ++ ["data: [DONE]\n\n"]

    stream = Stream.map(chunks, fn chunk -> chunk end)
    {:ok, %Req.Response{status: 200, body: stream}}
  end

  @doc """
  Returns a mock success response.
  """
  def mock_success_response do
    {:ok,
     %Req.Response{
       status: 200,
       body: %{
         "choices" => [
           %{"message" => %{"content" => "Generated response"}}
         ]
       }
     }}
  end

  @doc """
  Returns a mock OpenAI chat completion response.
  """
  def mock_openai_response(content \\ "Test response") do
    Jason.encode!(%{
      "id" => "chatcmpl-test123",
      "object" => "chat.completion",
      "created" => System.system_time(:second),
      "model" => "gpt-4",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 20,
        "total_tokens" => 30
      }
    })
  end

  @doc """
  Returns a mock Anthropic message response.
  """
  def mock_anthropic_response(content \\ "Test response") do
    Jason.encode!(%{
      "id" => "msg_test123",
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => content}],
      "model" => "claude-3-opus-20240229",
      "stop_reason" => "end_turn",
      "stop_sequence" => nil,
      "usage" => %{
        "input_tokens" => 10,
        "output_tokens" => 20
      }
    })
  end

  @doc """
  Returns a mock Google Gemini response.
  """
  def mock_gemini_response(content \\ "Test response") do
    Jason.encode!(%{
      "candidates" => [
        %{
          "content" => %{
            "parts" => [%{"text" => content}],
            "role" => "model"
          },
          "finishReason" => "STOP",
          "index" => 0
        }
      ],
      "usageMetadata" => %{
        "promptTokenCount" => 10,
        "candidatesTokenCount" => 20,
        "totalTokenCount" => 30
      }
    })
  end

  ## Test Assertion Helpers

  @doc """
  Asserts that a result is an error with a specific reason.
  """
  def assert_error({:error, reason}, expected_reason) when is_atom(expected_reason) do
    assert reason == expected_reason
  end

  def assert_error({:error, reason}, expected_reason) when is_binary(expected_reason) do
    assert String.contains?(reason, expected_reason)
  end

  @doc """
  Asserts that a result is successful and returns the unwrapped value.
  """
  def assert_ok({:ok, value}), do: value
  def assert_ok(other), do: flunk("Expected {:ok, _}, got: #{inspect(other)}")

  @doc """
  Waits for a process to complete or timeout.
  Useful for testing async operations.
  """
  def wait_for_completion(pid, timeout \\ 5000) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  end

  ## Memory and Resource Helpers

  @doc """
  Captures process memory usage before and after a function execution.
  Returns {result, memory_diff_kb}.
  """
  def measure_memory(fun) when is_function(fun, 0) do
    {memory_before, _} = :erlang.process_info(self(), :memory)
    result = fun.()
    {memory_after, _} = :erlang.process_info(self(), :memory)

    memory_diff_kb = div(memory_after - memory_before, 1024)
    {result, memory_diff_kb}
  end

  @doc """
  Times the execution of a function in milliseconds.
  Returns {result, time_ms}.
  """
  def measure_time(fun) when is_function(fun, 0) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    end_time = System.monotonic_time(:millisecond)

    {result, end_time - start_time}
  end
end
