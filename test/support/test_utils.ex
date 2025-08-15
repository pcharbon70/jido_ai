defmodule Jido.AI.TestUtils do
  @moduledoc """
  Test support utilities for the JidoAI package.

  Provides helpers for:
  - Isolated Keyring setup/teardown
  - Provider registry management
  - Common test fixtures
  - HTTP mocking helpers using Req.Test
  """

  import ExUnit.Assertions
  import Plug.Conn, only: [put_status: 2, put_resp_header: 3, send_resp: 3]

  ## Keyring Test Utilities
  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias JidoAI.Provider.Test

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
    Keyring.clear_all_session_values()

    # Return cleanup function
    fn -> Keyring.clear_all_session_values() end
  end

  @doc """
  Sets up keyring with test API keys for common providers.
  """
  def setup_test_keyring do
    cleanup_fn = setup_isolated_keyring()

    # Add test keys via session values
    Keyring.set_session_value(:openai_api_key, "test-openai-key")
    Keyring.set_session_value(:anthropic_api_key, "test-anthropic-key")
    Keyring.set_session_value(:google_api_key, "test-google-key")
    Keyring.set_session_value(:mistral_api_key, "test-mistral-key")

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
    %Model{
      provider: :openai,
      model: "gpt-4",
      temperature: nil,
      max_tokens: nil,
      max_retries: 3,
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
    %Model{
      provider: :anthropic,
      model: "claude-3-sonnet",
      temperature: nil,
      max_tokens: nil,
      max_retries: 3,
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
    %Model{
      provider: :google,
      model: "gemini-pro",
      temperature: nil,
      max_tokens: nil,
      max_retries: 3,
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
    %Model{
      provider: :mistral,
      model: "mistral-large",
      temperature: nil,
      max_tokens: nil,
      max_retries: 3,
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
    %Model{
      provider: :fake,
      model: "fake-model",
      temperature: nil,
      max_tokens: nil,
      max_retries: 3,
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
      module: Keyword.get(opts, :module, Test),
      api_key_name: to_string(name),
      base_url: Keyword.get(opts, :base_url, "https://api.#{name}.com"),
      headers: Keyword.get(opts, :headers, %{"Content-Type" => "application/json"}),
      models: Keyword.get(opts, :models, ["test-model-1", "test-model-2"])
    }

    Map.merge(base_config, Map.new(opts))
  end

  ## HTTP Mocking Helpers (using Req.Test)

  @doc """
  Sets up HTTP mocking using Req.Test.
  Returns a cleanup function.
  """
  def setup_http_mocking do
    # Req.Test is automatically set up via test_helper.exs
    # Return no-op cleanup function
    fn -> :ok end
  end

  @doc """
  Stubs a successful HTTP request with default OpenAI response.
  """
  def mock_http_success do
    Req.Test.stub(:base_test, fn conn ->
      conn
      |> Req.Test.json(%{
        "choices" => [
          %{"message" => %{"content" => "Generated response"}}
        ]
      })
    end)
  end

  @doc """
  Stubs a successful HTTP request with the given response.
  """
  def mock_http_success(url, response_body, opts \\ []) do
    status_code = Keyword.get(opts, :status_code, 200)

    Req.Test.stub(:base_test, fn conn ->
      # Verify URL matches if provided
      if url && conn.request_path != URI.parse(url).path do
        conn |> put_status(404) |> Req.Test.json(%{error: "URL not found"})
      else
        conn
        |> put_status(status_code)
        |> Req.Test.json(response_body)
      end
    end)
  end

  @doc """
  Stubs an HTTP error response with status and body or transport error.
  """
  def mock_http_error(status_or_url, body_or_error_reason \\ :timeout)

  def mock_http_error(status, body) when is_integer(status) do
    Req.Test.stub(:base_test, fn conn ->
      conn
      |> put_status(status)
      |> Req.Test.json(body)
    end)
  end

  def mock_http_error(url, error_reason) when is_binary(url) do
    Req.Test.stub(:base_test, fn conn ->
      # Verify URL matches if provided
      if url && conn.request_path != URI.parse(url).path do
        conn |> put_status(404) |> Req.Test.json(%{error: "URL not found"})
      else
        Req.Test.transport_error(conn, error_reason)
      end
    end)
  end

  @doc """
  Stubs an HTTP response with a specific status code and error body.
  """
  def mock_http_error_response(url, status_code, error_body) do
    Req.Test.stub(:base_test, fn conn ->
      # Verify URL matches if provided
      if url && conn.request_path != URI.parse(url).path do
        conn |> put_status(404) |> Req.Test.json(%{error: "URL not found"})
      else
        conn
        |> put_status(status_code)
        |> Req.Test.json(error_body)
      end
    end)
  end

  @doc """
  Stubs SSE stream with the given chunks.
  """
  def mock_sse_stream(chunks) do
    Req.Test.stub(:base_test, fn conn ->
      # Create a stream from the chunks
      stream = Stream.map(chunks, fn chunk -> chunk end)

      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> send_resp(200, stream)
    end)
  end

  @doc """
  Stubs SSE response with content chunks.
  """
  def mock_sse_response(content_chunks) do
    chunks =
      Enum.map(content_chunks, fn content ->
        "data: {\"choices\":[{\"delta\":{\"content\":\"#{content}\"}}]}\n\n"
      end) ++ ["data: [DONE]\n\n"]

    Req.Test.stub(:base_test, fn conn ->
      stream = Stream.map(chunks, fn chunk -> chunk end)

      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> send_resp(200, stream)
    end)
  end

  @doc """
  Returns a mock success response data structure.
  """
  def mock_success_response do
    %{
      "choices" => [
        %{"message" => %{"content" => "Generated response"}}
      ]
    }
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
