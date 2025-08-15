defmodule Jido.AI.Provider.AnthropicTest do
  @moduledoc """
  Tests for Anthropic provider implementation.
  """

  use Jido.AI.TestSupport.ProviderCase, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Anthropic

  describe "provider_info/0" do
    test "returns correct provider structure" do
      info = Anthropic.provider_info()

      assert %Provider{} = info
      assert info.id == :anthropic
      assert is_binary(info.name)
      assert is_binary(info.base_url)
      assert is_list(info.env)
      assert is_map(info.models)
    end
  end

  describe "basic validation" do
    setup do
      cleanup_fn = setup_isolated_keyring()
      on_exit(cleanup_fn)

      # Set up fake API key
      Application.put_env(:jido_ai, :anthropic_api_key, "fake-key")

      model = %Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 1000
      }

      %{model: model}
    end

    test "generate_text validates empty prompt", %{model: model} do
      assert {:error, reason} = Anthropic.generate_text(model, "", [])
      assert %Parameter{} = reason
    end

    test "generate_text with mocked success", %{model: model} do
      Req.Test.stub(:provider_case, fn conn ->
        conn
        |> Req.Test.json(%{
          "choices" => [%{"message" => %{"content" => "Generated response"}}]
        })
      end)

      assert {:ok, response} = Anthropic.generate_text(model, "test", [])
      assert is_binary(response)
    end
  end
end
