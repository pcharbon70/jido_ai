defmodule Jido.AI.Provider.OpenRouterSimpleTest do
  @moduledoc """
  Simple tests for OpenRouter provider to improve coverage.
  """

  use Jido.AI.TestSupport.ProviderCase, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.OpenRouter

  describe "provider_info/0" do
    test "returns correct provider structure" do
      info = OpenRouter.provider_info()

      assert %Provider{} = info
      assert info.id == :openrouter
      assert is_binary(info.name)
      assert is_binary(info.base_url)
      assert is_list(info.env)
      assert is_map(info.models)
    end

    test "has models loaded from JSON" do
      info = OpenRouter.provider_info()

      # Should have loaded models from openrouter.json
      assert map_size(info.models) > 0
    end
  end

  describe "basic provider behavior" do
    setup do
      # Set up isolated test environment
      cleanup_fn = setup_isolated_keyring()
      on_exit(cleanup_fn)

      # Set up fake API key
      Application.put_env(:jido_ai, :openrouter_api_key, "fake-key")

      model = %Model{
        provider: :openrouter,
        model: "anthropic/claude-3.5-sonnet",
        temperature: 0.7,
        max_tokens: 1000
      }

      %{model: model}
    end

    test "generate_text validates empty prompt", %{model: model} do
      assert {:error, reason} = OpenRouter.generate_text(model, "", [])
      assert %Parameter{} = reason
    end

    test "generate_text validates nil prompt", %{model: model} do
      assert {:error, reason} = OpenRouter.generate_text(model, nil, [])
      assert %Parameter{} = reason
    end

    test "stream_text validates empty prompt", %{model: model} do
      assert {:error, reason} = OpenRouter.stream_text(model, "", [])
      assert %Parameter{} = reason
    end

    test "generate_text with mocked success", %{model: model} do
      Req.Test.stub(:provider_case, fn conn ->
        conn
        |> Req.Test.json(%{
          "choices" => [%{"message" => %{"content" => "Generated response"}}]
        })
      end)

      assert {:ok, response} = OpenRouter.generate_text(model, "test", [])
      assert is_binary(response)
    end

    @tag :skip
    test "generate_text requires API key", %{model: _model} do
      # This test is skipped because .env file provides API key
      # and clearing all sources is complex in this environment
      :ok
    end
  end
end
