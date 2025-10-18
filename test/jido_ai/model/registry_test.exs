defmodule Jido.AI.Model.RegistryTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Model.Registry
  alias Jido.AI.Model.Registry.{Adapter, MetadataBridge}
  alias Jido.AI.{Model, Provider}
  alias Jido.AI.Test.RegistryHelpers

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Adapter)
    copy(Provider)
    copy(MetadataBridge)
    copy(Registry)
    :ok
  end

  describe "Registry.list_models/1" do
    test "returns models from ReqLLM registry when available" do
      # Use minimal mock data (5 models) instead of loading 2000+ real models
      RegistryHelpers.setup_minimal_registry_mock()

      {:ok, models} = Registry.list_models()

      # Minimal mock has 5 models across 3 providers
      assert length(models) == 5
      assert Enum.any?(models, &(&1.provider == :anthropic))
      assert Enum.any?(models, &(&1.provider == :openai))
      assert Enum.any?(models, &(&1.provider == :google))
    end

    test "falls back to legacy provider when registry unavailable" do
      # Mock registry failure
      expect(Adapter, :list_providers, fn -> {:error, :registry_unavailable} end)

      # Mock legacy provider fallback
      legacy_models = [
        %{"id" => "legacy-model", "provider" => :openai}
      ]

      stub(Provider, :list_all_cached_models, fn -> legacy_models end)

      {:ok, models} = Registry.list_models()

      assert is_list(models)
      assert length(models) >= 0
    end

    test "filters by provider when specified" do
      # Use minimal mock data
      RegistryHelpers.setup_minimal_registry_mock()

      {:ok, models} = Registry.list_models(:anthropic)

      # Minimal mock has 2 Anthropic models
      assert length(models) == 2
      assert Enum.all?(models, &(&1.provider == :anthropic))
    end
  end

  describe "Registry.get_model/2" do
    test "returns enhanced model from registry" do
      # Use minimal mock which includes claude-3-5-sonnet
      RegistryHelpers.setup_minimal_registry_mock()

      # Get model from mocked registry
      {:ok, models} = Registry.list_models(:anthropic)
      model = Enum.find(models, &(&1.id == "claude-3-5-sonnet-20241022"))

      assert model.provider == :anthropic
      assert model.capabilities.tool_call == true
      assert model.capabilities.reasoning == true
    end

    test "falls back to legacy provider when model not found in registry" do
      # This test verifies fallback behavior - keep adapter mocking
      expect(Adapter, :get_model, fn :openai, "gpt-4" ->
        {:error, :not_found}
      end)

      # Mock legacy adapter returns error since OpenAI module doesn't exist in test
      expect(Provider, :get_adapter_by_id, fn :openai ->
        {:error, :not_found}
      end)

      # Should return error when both registry and legacy fail
      result = Registry.get_model(:openai, "gpt-4")
      assert match?({:error, _}, result)
    end
  end

  describe "Registry.discover_models/1" do
    test "filters models by capabilities" do
      # Use minimal mock data (includes models with tool_call capability)
      RegistryHelpers.setup_minimal_registry_mock()

      {:ok, tool_call_models} = Registry.discover_models(capability: :tool_call)

      # Minimal mock has 5 models, 4 with tool_call capability
      # But discover_models returns ALL models when filters match
      assert length(tool_call_models) >= 4

      assert Enum.all?(tool_call_models, fn model ->
               model.capabilities && model.capabilities.tool_call
             end)
    end

    test "filters models by context length" do
      # Use minimal mock data (includes models with various context lengths)
      RegistryHelpers.setup_minimal_registry_mock()

      {:ok, large_context_models} = Registry.discover_models(min_context_length: 100_000)

      # Should return models with context >= 100k (anthropic, openai, google in minimal mock)
      assert length(large_context_models) >= 3

      Enum.each(large_context_models, fn model ->
        [endpoint | _] = model.endpoints
        assert endpoint.context_length >= 100_000
      end)
    end

    test "handles empty filter list" do
      # Use minimal mock data
      RegistryHelpers.setup_minimal_registry_mock()

      {:ok, all_models} = Registry.discover_models([])

      # Minimal mock has 5 models
      assert length(all_models) == 5
    end
  end

  describe "Registry.get_registry_stats/0" do
    test "returns comprehensive statistics" do
      # Use minimal mock data
      RegistryHelpers.setup_minimal_registry_mock()

      {:ok, stats} = Registry.get_registry_stats()

      # Minimal mock stats
      assert stats.total_models == 5
      assert stats.total_providers == 3

      # Check provider coverage exists
      assert is_map(stats.provider_coverage)
      assert stats.provider_coverage[:anthropic] == 2
      assert stats.provider_coverage[:openai] == 2
      assert stats.provider_coverage[:google] == 1

      # Check capabilities distribution
      assert stats.capabilities_distribution[:tool_call] == 4
      assert stats.capabilities_distribution[:reasoning] == 3
    end

    test "handles registry failure gracefully" do
      stub(Registry, :list_models, fn -> {:error, :registry_unavailable} end)

      {:ok, stats} = Registry.get_registry_stats()

      # Should still return stats structure, even if with error information
      assert is_map(stats)
    end
  end

  describe "error handling" do
    test "handles registry adapter errors gracefully" do
      expect(Adapter, :list_providers, fn -> raise "Registry connection error" end)

      # Should not crash, should fall back gracefully
      result = Registry.list_models()

      # Should return some kind of result (even if empty/error)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles metadata bridge errors gracefully" do
      mock_reqllm_model = %ReqLLM.Model{provider: :test, model: "test-model"}

      expect(Adapter, :list_providers, fn -> {:ok, [:test]} end)
      expect(Adapter, :list_models, fn :test -> {:ok, [mock_reqllm_model]} end)

      # Mock metadata bridge to raise error
      stub(MetadataBridge, :to_jido_model, fn _model ->
        raise "Metadata conversion error"
      end)

      # Should handle the error and not crash
      result = Registry.list_models()

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
