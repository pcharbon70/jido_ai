defmodule Jido.AI.ReqLlmBridge.Integration.KeyringAuthenticationIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  setup :set_mimic_global

  setup do
    copy(JidoKeys)
    copy(Keyring)
    copy(ReqLLM.Keys)
    :ok
  end

  # Helper functions to work with test-specific keyring
  defp set_provider(provider, key, keyring) do
    SessionAuthentication.set_for_provider(provider, key, self(), keyring)
  end

  setup do
    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_integration_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "keyring-authentication integration" do
    test "session values from keyring used in authentication headers", %{keyring: keyring} do
      # Set up session authentication
      set_provider(:openai, "session-openai-key", keyring)

      # Authentication should use session value
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})

      assert key == "session-openai-key"
      assert headers["authorization"] == "Bearer session-openai-key"
    end

    test "authentication precedence respects keyring session values", %{keyring: _keyring} do
      # Set session value
      SessionAuthentication.set_for_provider(:anthropic, "session-anthropic-key")

      # Attempt authentication with request override
      req_options = %{api_key: "request-override-key"}
      {:ok, headers, key} = Authentication.authenticate_for_provider(:anthropic, req_options)

      # Session value should take precedence
      assert key == "session-anthropic-key"
      assert headers["x-api-key"] == "session-anthropic-key"
      assert headers["anthropic-version"] == "2023-06-01"
    end

    test "per-request overrides work when no keyring session values", %{keyring: _keyring} do
      # Clear any existing session values
      SessionAuthentication.clear_for_provider(:openai)

      # Stub ReqLLM.Keys to extract and return api_key from req_options
      stub(ReqLLM.Keys, :get, fn :openai, %{api_key: "request-override-key"} ->
        {:ok, "request-override-key", :option}
      end)

      req_options = %{api_key: "request-override-key"}
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, req_options)

      assert key == "request-override-key"
      assert headers["authorization"] == "Bearer request-override-key"
    end

    test "provider key mapping works between systems", %{keyring: _keyring} do
      # Test different provider mappings
      providers_to_test = [
        {:openai, "sk-openai-test", "authorization", "Bearer sk-openai-test"},
        {:anthropic, "sk-ant-test", "x-api-key", "sk-ant-test"},
        {:google, "google-test-key", "x-goog-api-key", "google-test-key"},
        {:cloudflare, "cf-test-key", "x-auth-key", "cf-test-key"},
        {:openrouter, "sk-or-test", "authorization", "Bearer sk-or-test"}
      ]

      for {provider, test_key, expected_header, expected_value} <- providers_to_test do
        # Set session value for this provider
        SessionAuthentication.set_for_provider(provider, test_key)

        # Test authentication
        {:ok, headers, key} = Authentication.authenticate_for_provider(provider, %{})

        assert key == test_key
        assert headers[expected_header] == expected_value

        # Clean up for next iteration
        SessionAuthentication.clear_for_provider(provider)
      end
    end

    test "authentication fallback to environment when session empty", %{keyring: _keyring} do
      # Clear session values
      SessionAuthentication.clear_for_provider(:openai)

      # Stub JidoKeys to return nil (no global key)
      stub(JidoKeys, :get, fn :openai_api_key, nil -> nil end)

      # Mock environment fallback
      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        "env-openai-key"
      end)

      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})

      assert key == "env-openai-key"
      assert headers["authorization"] == "Bearer env-openai-key"
    end

    test "authentication error handling with proper jido error format", %{keyring: _keyring} do
      # Clear session values
      SessionAuthentication.clear_for_provider(:openai)

      # Stub JidoKeys to return nil (no global key)
      stub(JidoKeys, :get, fn :openai_api_key, nil -> nil end)

      # Mock environment to also fail
      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        nil
      end)

      {:error, reason} = Authentication.authenticate_for_provider(:openai, %{})

      assert reason == "Authentication error: API key not found: OPENAI_API_KEY"
    end
  end

  describe "cross-component session management" do
    test "keyring session values accessible by authentication", %{keyring: _keyring} do
      # Set values directly through session authentication
      SessionAuthentication.set_for_provider(:openai, "cross-component-key")

      # Authentication should be able to access it
      assert SessionAuthentication.has_session_auth?(:openai)
      {:session_auth, options} = SessionAuthentication.get_for_request(:openai, %{})
      assert options[:api_key] == "cross-component-key"

      # And use it in authentication headers
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "cross-component-key"
      assert headers["authorization"] == "Bearer cross-component-key"
    end

    test "session isolation maintained across components", %{keyring: _keyring} do
      # Set different values for different providers
      SessionAuthentication.set_for_provider(:openai, "openai-isolated")
      SessionAuthentication.set_for_provider(:anthropic, "anthropic-isolated")

      # Each should maintain its own isolation
      {:ok, openai_headers, openai_key} = Authentication.authenticate_for_provider(:openai, %{})

      {:ok, anthropic_headers, anthropic_key} =
        Authentication.authenticate_for_provider(:anthropic, %{})

      assert openai_key == "openai-isolated"
      assert anthropic_key == "anthropic-isolated"
      assert openai_headers["authorization"] == "Bearer openai-isolated"
      assert anthropic_headers["x-api-key"] == "anthropic-isolated"
    end

    test "session cleanup affects all components", %{keyring: _keyring} do
      # Set session values
      SessionAuthentication.set_for_provider(:openai, "before-cleanup")
      SessionAuthentication.set_for_provider(:anthropic, "before-cleanup")

      # Verify they exist
      assert SessionAuthentication.has_session_auth?(:openai)
      assert SessionAuthentication.has_session_auth?(:anthropic)

      # Clear all
      SessionAuthentication.clear_all()

      # Verify all are gone
      refute SessionAuthentication.has_session_auth?(:openai)
      refute SessionAuthentication.has_session_auth?(:anthropic)

      # Authentication should fall back to other methods
      # Stub JidoKeys to return nil (no global key)
      stub(JidoKeys, :get, fn
        :openai_api_key, nil -> nil
        :anthropic_api_key, nil -> nil
      end)

      stub(Keyring, :get_env_value, fn :default, _key, nil ->
        nil
      end)

      {:error, _} = Authentication.authenticate_for_provider(:openai, %{})
      {:error, _} = Authentication.authenticate_for_provider(:anthropic, %{})
    end

    test "cross-process session transfer integration", %{keyring: _keyring} do
      # Set authentication in current process
      SessionAuthentication.set_for_provider(:openai, "transfer-key")

      # Verify authentication works in current process
      {:ok, _headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "transfer-key"

      # Create target process and test transfer
      current_pid = self()

      task =
        Task.async(fn ->
          # Should not have authentication initially
          refute SessionAuthentication.has_session_auth?(:openai)

          # Transfer from parent
          transferred = SessionAuthentication.inherit_from(current_pid)
          assert :openai in transferred

          # Should now have authentication
          assert SessionAuthentication.has_session_auth?(:openai)

          # Authentication should work in child process
          {:ok, child_headers, child_key} = Authentication.authenticate_for_provider(:openai, %{})
          {child_key, child_headers["authorization"]}
        end)

      {child_key, child_auth_header} = Task.await(task)
      assert child_key == "transfer-key"
      assert child_auth_header == "Bearer transfer-key"
    end
  end

  describe "end-to-end provider authentication" do
    test "complete OpenAI authentication flow with keyring", %{keyring: _keyring} do
      # Test complete flow from session -> headers -> validation
      SessionAuthentication.set_for_provider(:openai, "sk-complete-openai-flow")

      # Authentication should work
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "sk-complete-openai-flow"
      assert headers["authorization"] == "Bearer sk-complete-openai-flow"

      # Headers should be retrievable
      retrieved_headers = Authentication.get_authentication_headers(:openai, %{})
      assert retrieved_headers["authorization"] == "Bearer sk-complete-openai-flow"

      # Validation should pass
      :ok = Authentication.validate_authentication(:openai, %{})
    end

    test "complete Anthropic authentication with session values", %{keyring: _keyring} do
      # Test Anthropic's specific header requirements
      SessionAuthentication.set_for_provider(:anthropic, "sk-ant-complete-flow")

      {:ok, headers, key} = Authentication.authenticate_for_provider(:anthropic, %{})
      assert key == "sk-ant-complete-flow"
      assert headers["x-api-key"] == "sk-ant-complete-flow"
      assert headers["anthropic-version"] == "2023-06-01"

      # Headers should include version
      retrieved_headers = Authentication.get_authentication_headers(:anthropic, %{})
      assert retrieved_headers["x-api-key"] == "sk-ant-complete-flow"
      assert retrieved_headers["anthropic-version"] == "2023-06-01"

      :ok = Authentication.validate_authentication(:anthropic, %{})
    end

    test "complete multi-provider authentication scenarios", %{keyring: _keyring} do
      # Set up multiple providers
      providers = [
        {:openai, "sk-multi-openai"},
        {:anthropic, "sk-ant-multi"},
        {:google, "google-multi-key"}
      ]

      # Set session values for all
      for {provider, key} <- providers do
        SessionAuthentication.set_for_provider(provider, key)
      end

      # Test each provider works correctly
      for {provider, expected_key} <- providers do
        {:ok, _headers, key} = Authentication.authenticate_for_provider(provider, %{})
        assert key == expected_key

        retrieved_headers = Authentication.get_authentication_headers(provider, %{})
        assert retrieved_headers != %{}

        :ok = Authentication.validate_authentication(provider, %{})
      end

      # Verify isolation - clearing one doesn't affect others
      SessionAuthentication.clear_for_provider(:openai)

      # OpenAI should fail
      # Stub JidoKeys to return nil (no global key)
      stub(JidoKeys, :get, fn :openai_api_key, nil -> nil end)

      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        nil
      end)

      {:error, _} = Authentication.authenticate_for_provider(:openai, %{})

      # Others should still work
      {:ok, _, "sk-ant-multi"} = Authentication.authenticate_for_provider(:anthropic, %{})
      {:ok, _, "google-multi-key"} = Authentication.authenticate_for_provider(:google, %{})
    end

    test "authentication failure recovery with keyring fallbacks", %{keyring: _keyring} do
      # Clear session values
      SessionAuthentication.clear_for_provider(:openai)

      # Stub JidoKeys to return nil (no global key)
      stub(JidoKeys, :get, fn :openai_api_key, nil -> nil end)

      # But provide keyring fallback
      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        "keyring-fallback-key"
      end)

      # Should successfully fall back to keyring
      {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
      assert key == "keyring-fallback-key"
      assert headers["authorization"] == "Bearer keyring-fallback-key"

      # And validation should work
      :ok = Authentication.validate_authentication(:openai, %{})
    end

    test "graceful degradation when all sources fail", %{keyring: _keyring} do
      # Clear session values
      SessionAuthentication.clear_for_provider(:openai)

      # Stub JidoKeys to return nil (no global key)
      stub(JidoKeys, :get, fn :openai_api_key, nil -> nil end)

      # Mock keyring to also fail
      stub(Keyring, :get_env_value, fn :default, :openai_api_key, nil ->
        nil
      end)

      # Should fail gracefully with proper error message
      {:error, reason} = Authentication.authenticate_for_provider(:openai, %{})
      assert reason == "Authentication error: API key not found: OPENAI_API_KEY"

      # Headers should return empty map on failure
      headers = Authentication.get_authentication_headers(:openai, %{})
      assert headers == %{}

      # Validation should also fail gracefully
      {:error, "Authentication error: API key not found: OPENAI_API_KEY"} =
        Authentication.validate_authentication(:openai, %{})
    end
  end
end
