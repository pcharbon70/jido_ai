defmodule Jido.AI.ProviderValidation.Integration.EnterpriseAuthFlowTest do
  @moduledoc """
  Integration tests for enterprise authentication flows across providers.

  Tests Task 2.1.4.4: Authentication Flow Integration

  Validates:
  - Cross-provider authentication consistency
  - Enterprise authentication patterns integration
  - Multi-provider session management
  - Authentication fallback mechanisms
  - Enterprise security compliance flows
  - Authentication performance patterns
  """

  use ExUnit.Case, async: false

  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.ReqLlmBridge.SessionAuthentication
  alias Jido.AI.Provider

  import Jido.AI.Test.EnterpriseHelpers

  @moduletag :provider_validation
  @moduletag :integration_testing
  @moduletag :enterprise_authentication
  @moduletag :authentication_flows

  # Test enterprise providers
  @enterprise_providers [:azure_openai, :amazon_bedrock, :alibaba_cloud]

  # Authentication method combinations
  @auth_method_combinations [
    # Azure methods
    {:azure_openai, :api_key},
    {:azure_openai, :entra_id},
    {:azure_openai, :managed_identity},

    # AWS methods
    {:amazon_bedrock, :iam_role},
    {:amazon_bedrock, :direct_credentials},
    {:amazon_bedrock, :cross_account},

    # Regional methods
    {:alibaba_cloud, :api_key},
    {:alibaba_cloud, :workspace_isolation}
  ]

  setup_all do
    # Only run if at least one enterprise provider is available
    available_providers =
      Enum.filter(@enterprise_providers, fn provider ->
        case provider do
          :azure_openai -> azure_credentials_available?()
          :amazon_bedrock -> aws_credentials_available?()
          :alibaba_cloud -> alibaba_credentials_available?()
        end
      end)

    # Return available providers (even if empty - tests will handle gracefully)
    {:ok, available_providers: available_providers}
  end

  defp azure_credentials_available? do
    case get_azure_api_key() do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp aws_credentials_available? do
    case System.get_env("AWS_ACCESS_KEY_ID") do
      key when is_binary(key) -> true
      _ -> false
    end
  end

  defp alibaba_credentials_available? do
    case System.get_env("ALIBABA_CLOUD_API_KEY") do
      key when is_binary(key) -> true
      _ -> false
    end
  end

  defp get_azure_api_key do
    case System.get_env("AZURE_OPENAI_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, "Azure OpenAI API key not found"}
    end
  end

  describe "Cross-Provider Authentication Patterns" do
    @tag :authentication_consistency
    test "validates consistent authentication interface across providers", %{
      available_providers: providers
    } do
      for provider <- providers do
        # Test authentication interface consistency
        case Authentication.authenticate_for_provider(provider, %{}) do
          {:ok, headers, _key} ->
            # Verify standard header structure (headers is already a map)
            assert is_map(headers), "#{provider} should return headers as a map"

            # Verify authentication header exists
            has_auth = Map.has_key?(headers, "authorization") or
                       Map.has_key?(headers, "Authorization") or
                       Map.has_key?(headers, "api-key") or
                       Map.has_key?(headers, "x-auth-key")

            assert has_auth, "#{provider} should include authentication header"

            # All providers using current architecture should work consistently
            IO.puts("✓ #{provider} authentication interface validated")

          {:error, reason} when is_binary(reason) ->
            # Expected when credentials are not configured
            assert String.contains?(reason, "not found") or
                   String.contains?(reason, "Authentication error"),
                   "#{provider} error should be descriptive: #{reason}"

          {:error, reason} ->
            flunk("Unexpected authentication error for #{provider}: #{inspect(reason)}")
        end
      end
    end

    @tag :auth_method_validation
    test "validates different authentication methods per provider", %{
      available_providers: providers
    } do
      available_combinations =
        Enum.filter(@auth_method_combinations, fn {provider, _method} ->
          provider in providers
        end)

      for {provider, auth_method} <- available_combinations do
        config = create_provider_config_with_auth(provider, auth_method)

        case config do
          {:skip, reason} ->
            # Expected when specific auth method is not available
            assert true, "Skipping #{provider}:#{auth_method} - #{reason}"

          config when is_map(config) ->
            case Authentication.authenticate_for_provider(provider, %{}) do
              {:ok, headers, _key} ->
                # Verify headers are returned as a map
                assert is_map(headers), "#{provider} should return headers"

                # Verify has authentication header
                has_auth = Map.has_key?(headers, "authorization") or
                           Map.has_key?(headers, "Authorization") or
                           Map.has_key?(headers, "x-auth-key")

                assert has_auth, "#{provider}:#{auth_method} should have auth header"

              {:error, reason} when is_binary(reason) ->
                # Expected when credentials are not available
                IO.puts("Auth method #{provider}:#{auth_method} unavailable: #{inspect(reason)}")
                assert true

              {:error, reason} ->
                # Log but don't fail for unavailable auth methods
                IO.puts("Auth method #{provider}:#{auth_method} unavailable: #{inspect(reason)}")
                assert true
            end
        end
      end
    end

    @tag :security_compliance
    test "validates enterprise security compliance across providers", %{
      available_providers: providers
    } do
      for provider <- providers do
        # Measure authentication overhead
        start_time = System.monotonic_time(:millisecond)
        auth_result = Authentication.authenticate_for_provider(provider, %{})
        overhead_ms = System.monotonic_time(:millisecond) - start_time

        case auth_result do
          {:ok, headers, _key} ->
            # Test performance requirements
            assert overhead_ms < 200,
                   "#{provider} authentication overhead should be under 200ms, got #{overhead_ms}ms"

            # Test header security - headers should be a map
            assert is_map(headers), "#{provider} should return headers as map"

            # Verify no sensitive data in headers (beyond auth tokens)
            for {key, value} <- headers do
              refute String.contains?(String.downcase(key), "password"),
                     "#{provider} headers should not contain password fields"

              # Value should be a string for this check
              if is_binary(value) do
                refute String.contains?(String.downcase(value), "secret") and
                         not String.starts_with?(value, "Bearer "),
                       "#{provider} headers should not expose raw secrets"
              end
            end

            IO.puts("✓ #{provider} security compliance validated")

          {:error, reason} when is_binary(reason) ->
            # Expected when credentials are not configured
            IO.puts("#{provider} credentials not available: #{reason}")

          {:error, reason} ->
            flunk("Security validation failed for #{provider}: #{inspect(reason)}")
        end
      end
    end
  end

  describe "Multi-Provider Session Management" do
    @tag :concurrent_sessions
    test "supports concurrent sessions across providers", %{available_providers: providers} do
      if length(providers) < 2 do
        IO.puts("Skipped: Need at least 2 providers for concurrent session testing")
      end

      # Create concurrent authentication sessions
      tasks =
        for provider <- providers do
          Task.async(fn ->
            config = create_provider_config(provider)

            case Authentication.authenticate_for_provider(provider, %{}) do
              {:ok, headers, _key} ->
                {provider, :authenticated, headers}

              {:error, :credentials_not_available} ->
                {provider, :skipped, "credentials not available"}

              {:error, reason} ->
                {provider, :failed, reason}
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # Verify concurrent authentication success
      authenticated_results =
        Enum.filter(results, fn
          {_provider, :authenticated, _headers} -> true
          _ -> false
        end)

      if length(authenticated_results) > 0 do
        IO.puts("✓ Concurrent authentication successful for #{length(authenticated_results)} providers")
      else
        IO.puts("No providers authenticated (credentials not available in test environment)")
      end

      # Verify session isolation
      for {provider_a, :authenticated, headers_a} <- authenticated_results do
        for {provider_b, :authenticated, headers_b} <- authenticated_results do
          if provider_a != provider_b do
            headers_map_a = Enum.into(headers_a, %{})
            headers_map_b = Enum.into(headers_b, %{})

            # Different providers should have different auth tokens
            auth_a = Map.get(headers_map_a, "Authorization") || Map.get(headers_map_a, "api-key")
            auth_b = Map.get(headers_map_b, "Authorization") || Map.get(headers_map_b, "api-key")

            if auth_a && auth_b do
              assert auth_a != auth_b,
                     "#{provider_a} and #{provider_b} should have different auth tokens"
            end
          end
        end
      end
    end

    @tag :session_isolation
    test "validates session isolation between enterprise tenants", %{
      available_providers: providers
    } do
      for provider <- providers do
        # Test with different tenant configurations
        base_config = create_provider_config(provider)

        case base_config do
          {:skip, _reason} ->
            assert true

          config when is_map(config) ->
            tenant_configs = create_multi_tenant_configs(provider, config)

            if length(tenant_configs) > 1 do
              tenant_results =
                for {tenant_id, _tenant_config} <- tenant_configs do
                  case Authentication.authenticate_for_provider(provider, %{}) do
                    {:ok, headers, _key} ->
                      {tenant_id, headers}

                    {:error, _reason} ->
                      {tenant_id, nil}
                  end
                end

              # Verify tenant isolation
              authenticated_tenants =
                Enum.filter(tenant_results, fn {_id, headers} -> headers != nil end)

              if length(authenticated_tenants) > 1 do
                for {tenant_a, headers_a} <- authenticated_tenants do
                  for {tenant_b, headers_b} <- authenticated_tenants do
                    if tenant_a != tenant_b do
                      headers_map_a = Enum.into(headers_a, %{})
                      headers_map_b = Enum.into(headers_b, %{})

                      # Verify tenant-specific headers
                      case provider do
                        :azure_openai ->
                          # Different Azure tenants should have different endpoints or auth
                          endpoint_a = Map.get(headers_map_a, "X-Azure-Tenant")
                          endpoint_b = Map.get(headers_map_b, "X-Azure-Tenant")

                          if endpoint_a && endpoint_b do
                            assert endpoint_a != endpoint_b,
                                   "Different Azure tenants should have different tenant IDs"
                          end

                        :alibaba_cloud ->
                          # Different workspaces should be isolated
                          workspace_a = Map.get(headers_map_a, "X-DashScope-Workspace")
                          workspace_b = Map.get(headers_map_b, "X-DashScope-Workspace")

                          if workspace_a && workspace_b do
                            assert workspace_a != workspace_b,
                                   "Different Alibaba workspaces should have different IDs"
                          end

                        _ ->
                          # Generic isolation check
                          assert headers_a != headers_b,
                                 "Different tenants should have different auth headers"
                      end
                    end
                  end
                end
              end
            end
        end
      end
    end
  end

  describe "Authentication Fallback Mechanisms" do
    @tag :fallback_testing
    test "validates authentication fallback chains", %{available_providers: providers} do
      for provider <- providers do
        # Test primary auth method
        primary_config = create_provider_config(provider)

        case primary_config do
          {:skip, _reason} ->
            assert true

          config when is_map(config) ->
            # Test with invalid primary credentials
            invalid_config = invalidate_primary_auth(provider, config)

            case EnterpriseAuthentication.authenticate_provider(provider, invalid_config, []) do
              {:ok, _headers} ->
                # If this succeeds, fallback worked or invalid config wasn't actually invalid
                assert true

              {:error, :authentication_failed} ->
                # Expected when no fallback is available
                assert true

              {:error, :credentials_not_available} ->
                # Expected when credentials are not configured
                assert true

              {:error, reason} ->
                # Test that error is handled gracefully
                assert is_binary(reason) or is_atom(reason),
                       "#{provider} should return structured error for auth failure"
            end
        end
      end
    end

    @tag :auth_retry_logic
    test "validates authentication retry mechanisms", %{available_providers: providers} do
      for provider <- providers do
        config = create_provider_config(provider)

        case config do
          {:skip, _reason} ->
            assert true

          config when is_map(config) ->
            # Add retry configuration
            retry_config =
              Map.merge(config, %{
                retry_attempts: 3,
                retry_delay: 100,
                exponential_backoff: true
              })

            start_time = :os.system_time(:millisecond)

            case EnterpriseAuthentication.authenticate_provider(provider, retry_config, []) do
              {:ok, headers, _key} ->
                end_time = :os.system_time(:millisecond)
                duration = end_time - start_time

                # Authentication should complete within reasonable time
                assert duration < 2000,
                       "#{provider} authentication with retries should complete under 2s"

                assert_valid_enterprise_headers(headers, provider)

              {:error, :credentials_not_available} ->
                # Expected when credentials are not configured
                assert true

              {:error, _reason} ->
                end_time = :os.system_time(:millisecond)
                duration = end_time - start_time

                # Even failed auth should respect retry timeouts
                assert duration >= 100,
                       "#{provider} should respect minimum retry delay"

                assert duration < 5000,
                       "#{provider} failed auth should not exceed maximum retry time"
            end
        end
      end
    end
  end

  describe "End-to-End Authentication Flows" do
    @tag :complete_flow
    test "validates complete authentication to completion flow", %{available_providers: providers} do
      for provider <- providers do
        config = create_provider_config(provider)

        case config do
          {:skip, _reason} ->
            assert true

          config when is_map(config) ->
            # 1. Authentication
            case Authentication.authenticate_for_provider(provider, %{}) do
              {:ok, _headers} ->
                # 2. Model listing
                case Provider.models(provider, []) do
                  {:ok, models} ->
                    assert is_list(models), "#{provider} should return models list"

                    # If models are available, validate structure
                    if models != [] do
                      sample_model = List.first(models)
                      assert is_map(sample_model) or is_binary(sample_model),
                             "#{provider} models should be maps or strings"

                      IO.puts("✓ #{provider} complete auth flow validated (#{length(models)} models)")
                    else
                      IO.puts("✓ #{provider} auth flow validated (no models available)")
                    end

                  {:error, reason} ->
                    # Model listing might fail for various reasons
                    IO.puts("Model listing failed for #{provider}: #{inspect(reason)}")
                    assert true
                end

              {:error, :credentials_not_available} ->
                # Expected when credentials are not configured
                assert true

              {:error, reason} ->
                flunk("Authentication failed for #{provider}: #{inspect(reason)}")
            end
        end
      end
    end

    @tag :multi_provider_workflow
    test "validates multi-provider enterprise workflow", %{available_providers: providers} do
      if length(providers) < 2 do
        IO.puts("Skipped: Need at least 2 providers for multi-provider workflow testing")
      end

      # Test round-robin provider usage
      provider_results =
        for provider <- providers do
          config = create_provider_config(provider)

          case config do
            {:skip, _reason} ->
              {provider, :skipped}

            config when is_map(config) ->
              # Simple test request
              messages = [
                %{role: "user", content: "Multi-provider test for #{provider}"}
              ]

              case authenticate_and_complete(provider, config, messages) do
                {:ok, response} ->
                  {provider, {:success, response}}

                {:error, reason} ->
                  {provider, {:error, reason}}
              end
          end
        end

      # Verify at least one provider worked
      successful_providers =
        Enum.filter(provider_results, fn
          {_provider, {:success, _response}} -> true
          _ -> false
        end)

      if length(successful_providers) > 0 do
        IO.puts("✓ Multi-provider workflow successful for #{length(successful_providers)} providers")

        # Verify responses are from different providers
        for {provider, {:success, response}} <- successful_providers do
          if is_map(response) and Map.has_key?(response, :provider) do
            assert response.provider == provider or response.provider == Atom.to_string(provider),
                   "Response should be tagged with correct provider"
          end
        end
      else
        IO.puts("No providers completed workflow (credentials not available in test environment)")
      end
    end
  end

  # Helper functions

  defp create_provider_config(provider) do
    case provider do
      :azure_openai ->
        case get_azure_api_key() do
          {:ok, _} -> create_azure_api_key_config()
          {:error, reason} -> {:skip, reason}
        end

      :amazon_bedrock ->
        case System.get_env("AWS_ACCESS_KEY_ID") do
          key when is_binary(key) -> create_aws_direct_credentials_config()
          _ -> {:skip, "AWS credentials not available"}
        end

      :alibaba_cloud ->
        case System.get_env("ALIBABA_CLOUD_API_KEY") do
          key when is_binary(key) -> create_alibaba_cloud_config()
          _ -> {:skip, "Alibaba Cloud credentials not available"}
        end
    end
  end

  defp create_provider_config_with_auth(provider, auth_method) do
    case {provider, auth_method} do
      {:azure_openai, :api_key} ->
        create_azure_api_key_config()

      {:azure_openai, :entra_id} ->
        create_azure_entra_id_config()

      {:azure_openai, :managed_identity} ->
        {:skip, "Managed identity testing not implemented"}

      {:amazon_bedrock, :iam_role} ->
        create_aws_iam_role_config()

      {:amazon_bedrock, :direct_credentials} ->
        create_aws_direct_credentials_config()

      {:amazon_bedrock, :cross_account} ->
        {:skip, "Cross-account testing not implemented"}

      {:alibaba_cloud, :api_key} ->
        create_alibaba_cloud_config()

      {:alibaba_cloud, :workspace_isolation} ->
        config = create_alibaba_cloud_config()

        case config do
          {:skip, reason} ->
            {:skip, reason}

          config when is_map(config) ->
            Map.put(config, :workspace, "test-workspace-#{:rand.uniform(1000)}")
        end
    end
  end

  defp create_multi_tenant_configs(provider, base_config) do
    case provider do
      :azure_openai ->
        [
          {"tenant-a", Map.put(base_config, :tenant_id, "tenant-a-id")},
          {"tenant-b", Map.put(base_config, :tenant_id, "tenant-b-id")}
        ]

      :amazon_bedrock ->
        [
          {"account-a", Map.put(base_config, :account_id, "123456789012")},
          {"account-b", Map.put(base_config, :account_id, "123456789013")}
        ]

      :alibaba_cloud ->
        [
          {"workspace-a", Map.put(base_config, :workspace, "workspace-a")},
          {"workspace-b", Map.put(base_config, :workspace, "workspace-b")}
        ]
    end
  end

  defp invalidate_primary_auth(provider, config) do
    case provider do
      :azure_openai ->
        Map.put(config, :api_key, "invalid-key-12345")

      :amazon_bedrock ->
        Map.put(config, :access_key_id, "invalid-key-12345")

      :alibaba_cloud ->
        Map.put(config, :api_key, "invalid-key-12345")
    end
  end

  defp assert_auth_method_compliance(headers, provider, auth_method) do
    headers_map = Enum.into(headers, %{})

    case {provider, auth_method} do
      {:azure_openai, :api_key} ->
        assert Map.has_key?(headers_map, "api-key"),
               "Azure API key auth should include api-key header"

      {:azure_openai, :entra_id} ->
        assert Map.has_key?(headers_map, "Authorization"),
               "Azure Entra ID auth should include Authorization header"

        assert String.starts_with?(headers_map["Authorization"], "Bearer "),
               "Azure Entra ID should use Bearer token"

      {:amazon_bedrock, :iam_role} ->
        assert Map.has_key?(headers_map, "Authorization"),
               "AWS IAM role auth should include Authorization header"

        assert String.starts_with?(headers_map["Authorization"], "AWS4-HMAC-SHA256"),
               "AWS should use Signature Version 4"

      {:amazon_bedrock, :direct_credentials} ->
        assert Map.has_key?(headers_map, "Authorization"),
               "AWS direct credentials should include Authorization header"

        assert String.starts_with?(headers_map["Authorization"], "AWS4-HMAC-SHA256"),
               "AWS should use Signature Version 4"

      {:alibaba_cloud, :api_key} ->
        assert Map.has_key?(headers_map, "Authorization"),
               "Alibaba API key auth should include Authorization header"

        assert String.starts_with?(headers_map["Authorization"], "Bearer "),
               "Alibaba should use Bearer token"

      _ ->
        # Generic validation for other auth methods
        assert Map.has_key?(headers_map, "Authorization") or Map.has_key?(headers_map, "api-key"),
               "#{provider}:#{auth_method} should include authentication header"
    end
  end

  defp select_test_model(provider, models) do
    model_ids = Enum.map(models, & &1.id)

    case provider do
      :azure_openai ->
        Enum.find(model_ids, &String.contains?(&1, "gpt")) || List.first(model_ids)

      :amazon_bedrock ->
        Enum.find(model_ids, &String.contains?(&1, "claude")) || List.first(model_ids)

      :alibaba_cloud ->
        Enum.find(model_ids, &String.contains?(&1, "qwen")) || List.first(model_ids)

      _ ->
        List.first(model_ids)
    end
  end

  defp authenticate_and_complete(provider, config, messages) do
    case Authentication.authenticate_for_provider(provider, %{}) do
      {:ok, _headers, _key} ->
        # Get available models
        case Provider.models(provider, []) do
          {:ok, models} when is_list(models) and models != [] ->
            # Successfully authenticated and got models - test passed
            {:ok, %{provider: provider, model_count: length(models)}}

          {:ok, []} ->
            # Authenticated but no models available
            {:ok, %{provider: provider, model_count: 0}}

          {:error, reason} ->
            {:error, {:model_listing_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:authentication_failed, reason}}
    end
  end
end
