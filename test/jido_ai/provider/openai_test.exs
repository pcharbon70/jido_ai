defmodule Jido.AI.Provider.OpenAITest do
  @moduledoc """
  Tests for OpenAI provider implementation.
  """

  use Jido.AI.TestSupport.ProviderCase, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.OpenAI

  describe "provider_info/0" do
    test "returns correct provider structure" do
      info = OpenAI.provider_info()

      assert %Provider{} = info
      assert info.id == :openai
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
      Application.put_env(:jido_ai, :openai_api_key, "fake-key")

      model = %Model{
        provider: :openai,
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      }

      %{model: model}
    end

    test "generate_text validates empty prompt", %{model: model} do
      assert {:error, reason} = OpenAI.generate_text(model, "", [])
      assert %Parameter{} = reason
    end

    test "generate_text with mocked success", %{model: model} do
      Req.Test.stub(:provider_case, fn conn ->
        conn
        |> Req.Test.json(%{
          "choices" => [%{"message" => %{"content" => "Generated response"}}]
        })
      end)

      assert {:ok, response} = OpenAI.generate_text(model, "test", [])
      assert is_binary(response)
    end
  end
end
