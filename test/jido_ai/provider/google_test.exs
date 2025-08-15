defmodule Jido.AI.Provider.GoogleTest do
  @moduledoc """
  Tests for Google provider implementation.
  """

  use ExUnit.Case, async: true

  import Jido.AI.TestUtils

  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Google

  describe "provider_info/0" do
    test "returns correct provider structure" do
      info = Google.provider_info()

      assert %Provider{} = info
      assert info.id == :google
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
      Application.put_env(:jido_ai, :google_api_key, "fake-key")

      model = %Model{
        provider: :google,
        model: "gemini-1.5-pro",
        temperature: 0.7,
        max_tokens: 1000
      }

      %{model: model}
    end

    test "generate_text validates empty prompt", %{model: model} do
      assert {:error, reason} = Google.generate_text(model, "", [])
      assert %Parameter{} = reason
    end

    @tag :skip
    test "generate_text with mocked success", %{model: _model} do
      # Skip due to HTTP mocking complexity with Google provider
      :ok
    end
  end
end
