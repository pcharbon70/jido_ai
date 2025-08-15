defmodule Jido.AI.TestSupport.Fixtures do
  @moduledoc """
  Test fixtures for AI provider testing.

  Provides common data structures and mock responses used across test suites.
  """

  alias Jido.AI.{Model, Provider}

  @doc """
  Default successful OpenAI-style API response.
  """
  def success_body do
    %{
      "id" => "chatcmpl-test123",
      "object" => "chat.completion",
      "created" => 1_234_567_890,
      "model" => "test-model",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => "Test response from AI"
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 5,
        "total_tokens" => 15
      }
    }
  end

  @doc """
  OpenAI-style error response.
  """
  def error_body(message \\ "Test error") do
    %{
      "error" => %{
        "message" => message,
        "type" => "invalid_request_error",
        "code" => "test_error"
      }
    }
  end

  @doc """
  Server-Sent Event chunks for streaming responses.
  """
  def sse_events do
    [
      %{
        "id" => "chatcmpl-stream1",
        "object" => "chat.completion.chunk",
        "created" => 1_234_567_890,
        "model" => "test-model",
        "choices" => [
          %{
            "index" => 0,
            "delta" => %{"content" => "Hello"},
            "finish_reason" => nil
          }
        ]
      },
      %{
        "id" => "chatcmpl-stream2",
        "object" => "chat.completion.chunk",
        "created" => 1_234_567_890,
        "model" => "test-model",
        "choices" => [
          %{
            "index" => 0,
            "delta" => %{"content" => " world!"},
            "finish_reason" => nil
          }
        ]
      },
      %{
        "id" => "chatcmpl-stream3",
        "object" => "chat.completion.chunk",
        "created" => 1_234_567_890,
        "model" => "test-model",
        "choices" => [
          %{
            "index" => 0,
            "delta" => %{},
            "finish_reason" => "stop"
          }
        ]
      }
    ]
  end

  @doc """
  Creates a test Model struct.
  """
  def model_fixture(overrides \\ []) do
    defaults = [
      provider: :fake,
      model: "fake-model",
      id: "fake-model",
      name: "Fake Model",
      temperature: 0.7,
      max_tokens: 1000,
      max_retries: 3
    ]

    struct(Model, Keyword.merge(defaults, overrides))
  end

  @doc """
  Creates a test Provider struct.
  """
  def provider_fixture(overrides \\ []) do
    defaults = [
      id: :fake,
      name: "Fake Provider",
      base_url: "https://fake.test/v1",
      env: [:fake_api_key],
      doc: "Test provider",
      models: %{}
    ]

    struct(Provider, Keyword.merge(defaults, overrides))
  end

  @doc """
  Default OpenAI-style chat completion request body.
  """
  def chat_completion_body do
    %{
      "model" => "test-model",
      "messages" => [
        %{
          "role" => "user",
          "content" => "Test prompt"
        }
      ],
      "temperature" => 0.7,
      "max_tokens" => 1000
    }
  end
end
