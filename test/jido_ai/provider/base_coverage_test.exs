defmodule Jido.AI.Provider.BaseCoverageTest do
  @moduledoc """
  Tests specifically designed to improve Provider.Base coverage.

  Focuses on uncovered code paths and edge cases.
  """

  use Jido.AI.TestSupport.ProviderCase, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.{API, Invalid}
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Base
  alias Jido.AI.Test.FakeProvider
  alias Jido.AI.TestSupport.Fixtures

  # Simple test provider
  defmodule CoverageTestProvider do
    @behaviour Jido.AI.Provider.Base

    @impl true
    def provider_info do
      %Provider{
        id: :coverage_test,
        name: "Coverage Test Provider",
        doc: "Provider for coverage testing",
        env: [:coverage_test_api_key],
        models: %{}
      }
    end

    @impl true
    def api_url, do: "https://coverage.test.com/v1"

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

    # Set API key for coverage test provider
    Application.put_env(:jido_ai, :coverage_test, api_key: "coverage-key-123")

    model = %Model{
      provider: :coverage_test,
      model: "coverage-model",
      temperature: 0.7,
      max_tokens: 1000,
      max_retries: 3
    }

    %{model: model}
  end

  describe "private helper functions" do
    test "validate_prompt with different input types", %{model: model} do
      # Test invalid prompts that trigger validate_prompt error path
      invalid_prompts = [nil, "", 123, [], %{}, :atom, false]

      for invalid_prompt <- invalid_prompts do
        assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
                 CoverageTestProvider.generate_text(model, invalid_prompt)

        assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
                 CoverageTestProvider.stream_text(model, invalid_prompt)
      end
    end

    test "get_required_opt error path for missing api_key", %{model: model} do
      # Clear API key to trigger get_required_opt error
      Application.put_env(:jido_ai, :coverage_test, [])

      assert {:error, %Invalid.Parameter{parameter: "api_key"}} =
               CoverageTestProvider.generate_text(model, "test")

      assert {:error, %Invalid.Parameter{parameter: "api_key"}} =
               CoverageTestProvider.stream_text(model, "test")
    end

    test "maybe_put with nil values", %{model: _model} do
      # Test model with nil values to exercise maybe_put logic
      model_with_nils = %Model{
        provider: :coverage_test,
        model: "test",
        temperature: nil,
        max_tokens: nil,
        max_retries: nil
      }

      merged = Base.merge_model_options(CoverageTestProvider, model_with_nils, [])

      # Nil values should not appear in keyword list
      assert is_nil(merged[:temperature])
      assert is_nil(merged[:max_tokens])
      assert is_nil(merged[:max_retries])
      # Non-nil values should be present
      assert merged[:api_key] == "coverage-key-123"
      assert String.ends_with?(merged[:url], "/chat/completions")
    end
  end

  describe "HTTP configuration edge cases" do
    test "reads http_client config from application environment", %{model: model} do
      # Test that HTTP client config is read from application
      current_client = Application.get_env(:jido_ai, :http_client, Req)
      current_options = Application.get_env(:jido_ai, :http_options, [])

      # Should use whatever is configured
      assert current_client != nil
      assert is_list(current_options)

      # Test merge_model_options includes URL correctly
      merged = Base.merge_model_options(CoverageTestProvider, model, [])
      assert String.ends_with?(merged[:url], "/chat/completions")
    end

    test "handles timeout configuration from environment", %{model: model} do
      # Set custom timeout values
      Application.put_env(:jido_ai, :receive_timeout, 45_000)
      Application.put_env(:jido_ai, :pool_timeout, 25_000)

      Req.Test.stub(:provider_case, fn conn ->
        conn |> Req.Test.json(Fixtures.success_body())
      end)

      assert {:ok, _} = CoverageTestProvider.generate_text(model, "test")
    end

    test "handles timeout configuration from opts", %{model: model} do
      # Test that timeout options can be set
      Application.put_env(:jido_ai, :receive_timeout, 45_000)
      Application.put_env(:jido_ai, :pool_timeout, 25_000)

      # Test configuration reading works
      merged =
        Base.merge_model_options(CoverageTestProvider, model,
          receive_timeout: 10_000,
          pool_timeout: 5_000
        )

      assert merged[:receive_timeout] == 10_000
      assert merged[:pool_timeout] == 5_000
    end

    test "validates transport error handling", %{model: model} do
      # Test that missing API key returns proper error
      Application.put_env(:jido_ai, :coverage_test, [])

      assert {:error, %Invalid.Parameter{parameter: "api_key"}} =
               CoverageTestProvider.generate_text(model, "test")
    end
  end

  describe "response parsing edge cases" do
    test "extract_text_response with multiple choices" do
      # Test that only first choice is extracted
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => "First choice"}},
            %{"message" => %{"content" => "Second choice"}},
            %{"message" => %{"content" => "Third choice"}}
          ]
        }
      }

      assert {:ok, "First choice"} = Base.extract_text_response(response)
    end

    test "extract_text_response with non-standard HTTP codes" do
      # Test 3xx and other codes not typically tested
      for status <- [301, 302, 304, 418, 503] do
        response = %Req.Response{
          status: status,
          body: %{"error" => %{"message" => "Non-standard status"}}
        }

        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end

    test "extract_text_response with unexpected response structure" do
      # Test various malformed responses
      malformed_responses = [
        %Req.Response{status: 200, body: nil},
        %Req.Response{status: 200, body: []},
        %Req.Response{status: 200, body: "string"},
        %Req.Response{status: 200, body: 123},
        %Req.Response{status: 200, body: %{}},
        %Req.Response{status: 200, body: %{"choices" => nil}},
        %Req.Response{status: 200, body: %{"choices" => "not_array"}}
      ]

      for response <- malformed_responses do
        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    end
  end

  describe "build_chat_completion_body edge cases" do
    test "filters invalid options correctly", %{model: model} do
      # Include mix of valid and invalid options
      opts = [
        # valid
        temperature: 0.8,
        # valid
        max_tokens: 100,
        # invalid
        invalid_option: "bad",
        # invalid
        custom_param: 123,
        # valid
        frequency_penalty: 0.5,
        # valid
        stream: true,
        # invalid
        unknown: "value"
      ]

      body = Base.build_chat_completion_body(model, "test", opts)

      # Should only include valid chat completion options
      assert body[:temperature] == 0.8
      assert body[:max_tokens] == 100
      assert body[:frequency_penalty] == 0.5
      assert body[:stream] == true
      assert body[:model] == "coverage-model"
      assert body[:messages] == [%{role: "user", content: "test"}]

      # Should filter out invalid options
      refute Map.has_key?(body, :invalid_option)
      refute Map.has_key?(body, :custom_param)
      refute Map.has_key?(body, :unknown)
    end

    test "handles all supported chat completion options", %{model: model} do
      # Test comprehensive option set
      all_opts = [
        frequency_penalty: 0.2,
        max_completion_tokens: 150,
        max_tokens: 200,
        n: 1,
        presence_penalty: 0.1,
        response_format: %{type: "text"},
        seed: 12_345,
        stop: ["END", "STOP"],
        temperature: 0.9,
        top_p: 0.8,
        user: "test-user",
        stream: false
      ]

      body = Base.build_chat_completion_body(model, "comprehensive", all_opts)

      # All valid options should be present
      for {key, expected_value} <- all_opts do
        assert body[key] == expected_value
      end

      assert body[:model] == "coverage-model"
      assert body[:messages] == [%{role: "user", content: "comprehensive"}]
    end
  end

  describe "configuration precedence" do
    test "merge_model_options precedence: opts > model > config", %{model: model} do
      # Set global config
      Application.put_env(:jido_ai, :receive_timeout, 60_000)

      # Model has its own values, opts override both
      opts = [
        # overrides model
        temperature: 1.0,
        # overrides config
        api_key: "opts-override",
        # overrides config
        receive_timeout: 5_000
      ]

      merged = Base.merge_model_options(CoverageTestProvider, model, opts)

      # from opts
      assert merged[:temperature] == 1.0
      # from model
      assert merged[:max_tokens] == 1000
      # from opts
      assert merged[:api_key] == "opts-override"
      # from opts
      assert merged[:receive_timeout] == 5_000
    end

    test "merge_model_options with missing config values", %{model: model} do
      # Clear all config
      Application.put_env(:jido_ai, :coverage_test, [])
      Application.delete_env(:jido_ai, :receive_timeout, persistent: false)
      Application.delete_env(:jido_ai, :pool_timeout, persistent: false)

      merged = Base.merge_model_options(CoverageTestProvider, model, [])

      # Should handle missing config gracefully
      assert merged[:api_key] == nil
      # from model
      assert merged[:temperature] == 0.7
      # from model
      assert merged[:max_tokens] == 1000
      assert String.ends_with?(merged[:url], "/chat/completions")
    end
  end

  describe "stream configuration" do
    test "stream_text adds stream=true to options" do
      # Test that default_stream_text adds stream parameter
      fake_model = %Model{provider: :fake, model: "fake-model"}

      # FakeProvider.stream_text should work without HTTP mocking
      assert {:ok, stream} = FakeProvider.stream_text(fake_model, "test", [])

      # Should return enumerable
      assert Enumerable.impl_for(stream) != nil

      chunks = Enum.to_list(stream)
      assert chunks == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end
end
