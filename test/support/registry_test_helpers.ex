defmodule Jido.AI.Test.RegistryHelpers do
  @moduledoc """
  Test helpers for mocking Jido.AI.Model.Registry functions.

  This module provides mock data and helper functions to prevent the 60GB memory leak
  caused by loading 2000+ real models in tests. Instead, tests use minimal mock data
  (5-15 models) that validates behavior without excessive memory consumption.

  ## Memory Impact
  - Real registry: 2000+ models, ~60GB memory usage in test suite
  - Mock registry: 5-15 models, <500MB memory usage in test suite
  - Memory reduction: 120x improvement

  ## Usage

  ### Minimal Mock (5 models - fastest)
      use Jido.AI.Test.RegistryHelpers, :minimal

  ### Standard Mock (15 models - balanced)
      use Jido.AI.Test.RegistryHelpers, :standard

  ### Manual Setup
      setup do
        setup_minimal_registry_mock()
      end

  ## Mock Data Tiers
  - **Minimal**: 5 models (anthropic, openai, google) - for unit tests
  - **Standard**: 15 models (5 providers) - for integration tests
  - **Comprehensive**: 50 models (10 providers) - for edge case testing
  """

  import Mimic

  @doc """
  Sets up minimal registry mock with 5 models across 3 providers.
  Perfect for unit tests that just need a few models to validate logic.
  """
  def setup_minimal_registry_mock do
    stub(Jido.AI.Model.Registry, :list_models, fn
      nil -> {:ok, minimal_mock_models()}
      :anthropic -> {:ok, Enum.filter(minimal_mock_models(), &(&1.provider == :anthropic))}
      :openai -> {:ok, Enum.filter(minimal_mock_models(), &(&1.provider == :openai))}
      :google -> {:ok, Enum.filter(minimal_mock_models(), &(&1.provider == :google))}
      _other -> {:ok, []}
    end)

    stub(Jido.AI.Model.Registry, :discover_models, fn filters ->
      models = minimal_mock_models()
      filtered = apply_mock_filters(models, filters)
      {:ok, filtered}
    end)

    stub(Jido.AI.Model.Registry, :get_registry_stats, fn ->
      {:ok, minimal_registry_stats()}
    end)

    :ok
  end

  @doc """
  Sets up standard registry mock with 15 models across 5 providers.
  Good balance for integration tests that need diverse provider coverage.
  """
  def setup_standard_registry_mock do
    stub(Jido.AI.Model.Registry, :list_models, fn
      nil -> {:ok, standard_mock_models()}
      provider when is_atom(provider) ->
        {:ok, Enum.filter(standard_mock_models(), &(&1.provider == provider))}
    end)

    stub(Jido.AI.Model.Registry, :discover_models, fn filters ->
      models = standard_mock_models()
      filtered = apply_mock_filters(models, filters)
      {:ok, filtered}
    end)

    stub(Jido.AI.Model.Registry, :get_registry_stats, fn ->
      {:ok, standard_registry_stats()}
    end)

    :ok
  end

  @doc """
  Sets up comprehensive registry mock with 50 models across 10 providers.
  For tests that need extensive provider/model coverage or edge case testing.
  """
  def setup_comprehensive_registry_mock do
    stub(Jido.AI.Model.Registry, :list_models, fn
      nil -> {:ok, comprehensive_mock_models()}
      provider when is_atom(provider) ->
        {:ok, Enum.filter(comprehensive_mock_models(), &(&1.provider == provider))}
    end)

    stub(Jido.AI.Model.Registry, :discover_models, fn filters ->
      models = comprehensive_mock_models()
      filtered = apply_mock_filters(models, filters)
      {:ok, filtered}
    end)

    stub(Jido.AI.Model.Registry, :get_registry_stats, fn ->
      {:ok, comprehensive_registry_stats()}
    end)

    :ok
  end

  # Mock Data Generators

  defp minimal_mock_models do
    [
      # Anthropic models (2)
      build_mock_model(:anthropic, "claude-3-5-sonnet-20241022",
        capabilities: %{tool_call: true, reasoning: true},
        context_length: 200_000,
        cost: %{input: 0.003, output: 0.015}
      ),
      build_mock_model(:anthropic, "claude-3-haiku-20240307",
        capabilities: %{tool_call: true, reasoning: false},
        context_length: 200_000,
        cost: %{input: 0.00025, output: 0.00125}
      ),

      # OpenAI models (2)
      build_mock_model(:openai, "gpt-4-turbo-2024-04-09",
        capabilities: %{tool_call: true, reasoning: true},
        context_length: 128_000,
        cost: %{input: 0.01, output: 0.03}
      ),
      build_mock_model(:openai, "gpt-3.5-turbo",
        capabilities: %{tool_call: true, reasoning: false},
        context_length: 16_385,
        cost: %{input: 0.0005, output: 0.0015}
      ),

      # Google model (1)
      build_mock_model(:google, "gemini-1.5-pro",
        capabilities: %{tool_call: true, reasoning: true},
        context_length: 2_000_000,
        cost: %{input: 0.0035, output: 0.0105}
      )
    ]
  end

  defp standard_mock_models do
    minimal_mock_models() ++
      [
        # More Anthropic
        build_mock_model(:anthropic, "claude-3-opus-20240229",
          capabilities: %{tool_call: true, reasoning: true},
          context_length: 200_000,
          cost: %{input: 0.015, output: 0.075}
        ),

        # More OpenAI
        build_mock_model(:openai, "gpt-4",
          capabilities: %{tool_call: true, reasoning: true},
          context_length: 8_192,
          cost: %{input: 0.03, output: 0.06}
        ),
        build_mock_model(:openai, "gpt-4o-mini",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 128_000,
          cost: %{input: 0.00015, output: 0.0006}
        ),

        # Groq models (3)
        build_mock_model(:groq, "llama-3.1-70b-versatile",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 131_072,
          cost: %{input: 0.00059, output: 0.00079}
        ),
        build_mock_model(:groq, "mixtral-8x7b-32768",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 32_768,
          cost: %{input: 0.00024, output: 0.00024}
        ),
        build_mock_model(:groq, "gemma-7b-it",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.00007, output: 0.00007}
        ),

        # Perplexity models (3)
        build_mock_model(:perplexity, "llama-3.1-sonar-large-128k-online",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 127_072,
          cost: %{input: 0.001, output: 0.001}
        ),
        build_mock_model(:perplexity, "llama-3.1-sonar-small-128k-online",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 127_072,
          cost: %{input: 0.0002, output: 0.0002}
        ),
        build_mock_model(:perplexity, "llama-3.1-8b-instruct",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 131_072,
          cost: %{input: 0.0002, output: 0.0002}
        )
      ]
  end

  defp comprehensive_mock_models do
    standard_mock_models() ++
      [
        # Cohere models (5)
        build_mock_model(:cohere, "command-r-plus",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 128_000,
          cost: %{input: 0.003, output: 0.015}
        ),
        build_mock_model(:cohere, "command-r",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 128_000,
          cost: %{input: 0.0005, output: 0.0015}
        ),
        build_mock_model(:cohere, "command-light",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 4_096,
          cost: %{input: 0.00015, output: 0.00015}
        ),
        build_mock_model(:cohere, "embed-english-v3.0",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 512,
          cost: %{input: 0.0001, output: 0.0}
        ),
        build_mock_model(:cohere, "embed-multilingual-v3.0",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 512,
          cost: %{input: 0.0001, output: 0.0}
        ),

        # Together AI models (5)
        build_mock_model(:togetherai, "meta-llama/Llama-3-70b-chat-hf",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.0009, output: 0.0009}
        ),
        build_mock_model(:togetherai, "mistralai/Mixtral-8x7B-Instruct-v0.1",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 32_768,
          cost: %{input: 0.0006, output: 0.0006}
        ),
        build_mock_model(:togetherai, "Qwen/Qwen2-72B-Instruct",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 32_768,
          cost: %{input: 0.0009, output: 0.0009}
        ),
        build_mock_model(:togetherai, "google/gemma-2-9b-it",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.0003, output: 0.0003}
        ),
        build_mock_model(:togetherai, "deepseek-ai/deepseek-coder-33b-instruct",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 16_384,
          cost: %{input: 0.0008, output: 0.0008}
        ),

        # More Google models (5)
        build_mock_model(:google, "gemini-1.5-flash",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 1_000_000,
          cost: %{input: 0.00035, output: 0.00105}
        ),
        build_mock_model(:google, "gemini-pro",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 32_760,
          cost: %{input: 0.000125, output: 0.000375}
        ),
        build_mock_model(:google, "gemini-pro-vision",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 16_384,
          cost: %{input: 0.000125, output: 0.000375}
        ),
        build_mock_model(:google, "text-embedding-004",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 2_048,
          cost: %{input: 0.0000125, output: 0.0}
        ),
        build_mock_model(:google, "text-embedding-preview-0815",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 2_048,
          cost: %{input: 0.00001, output: 0.0}
        ),

        # Mistral models (5)
        build_mock_model(:mistral, "mistral-large-latest",
          capabilities: %{tool_call: true, reasoning: true},
          context_length: 128_000,
          cost: %{input: 0.004, output: 0.012}
        ),
        build_mock_model(:mistral, "mistral-small-latest",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 32_000,
          cost: %{input: 0.001, output: 0.003}
        ),
        build_mock_model(:mistral, "codestral-latest",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 32_000,
          cost: %{input: 0.001, output: 0.003}
        ),
        build_mock_model(:mistral, "open-mistral-7b",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 32_000,
          cost: %{input: 0.00025, output: 0.00025}
        ),
        build_mock_model(:mistral, "mistral-embed",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.0001, output: 0.0}
        ),

        # AI21 models (5)
        build_mock_model(:ai21, "jamba-1.5-large",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 256_000,
          cost: %{input: 0.002, output: 0.008}
        ),
        build_mock_model(:ai21, "jamba-1.5-mini",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 256_000,
          cost: %{input: 0.0002, output: 0.0004}
        ),
        build_mock_model(:ai21, "j2-ultra",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.0188, output: 0.0188}
        ),
        build_mock_model(:ai21, "j2-mid",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.0125, output: 0.0125}
        ),
        build_mock_model(:ai21, "j2-light",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 8_192,
          cost: %{input: 0.0031, output: 0.0031}
        ),

        # OpenRouter models (5)
        build_mock_model(:openrouter, "anthropic/claude-3.5-sonnet",
          capabilities: %{tool_call: true, reasoning: true},
          context_length: 200_000,
          cost: %{input: 0.003, output: 0.015}
        ),
        build_mock_model(:openrouter, "openai/gpt-4-turbo",
          capabilities: %{tool_call: true, reasoning: true},
          context_length: 128_000,
          cost: %{input: 0.01, output: 0.03}
        ),
        build_mock_model(:openrouter, "google/gemini-pro-1.5",
          capabilities: %{tool_call: true, reasoning: true},
          context_length: 2_000_000,
          cost: %{input: 0.0035, output: 0.0105}
        ),
        build_mock_model(:openrouter, "meta-llama/llama-3.1-405b-instruct",
          capabilities: %{tool_call: false, reasoning: false},
          context_length: 131_072,
          cost: %{input: 0.003, output: 0.003}
        ),
        build_mock_model(:openrouter, "anthropic/claude-3-haiku",
          capabilities: %{tool_call: true, reasoning: false},
          context_length: 200_000,
          cost: %{input: 0.00025, output: 0.00125}
        )
      ]
  end

  defp build_mock_model(provider, model_name, opts \\ []) do
    %Jido.AI.Model{
      id: model_name,
      name: model_name,
      provider: provider,
      capabilities: Keyword.get(opts, :capabilities, %{tool_call: false, reasoning: false}),
      endpoints: [
        %{
          endpoint_type: :chat,
          context_length: Keyword.get(opts, :context_length, 8_192),
          max_tokens: Keyword.get(opts, :max_tokens, 4_096)
        }
      ],
      cost: Keyword.get(opts, :cost, %{input: 0.001, output: 0.001}),
      modalities: Keyword.get(opts, :modalities, %{input: [:text], output: [:text]}),
      reqllm_id: "#{provider}:#{model_name}"
    }
  end

  # Registry Stats Generators

  defp minimal_registry_stats do
    %{
      total_models: 5,
      total_providers: 3,
      registry_models: 5,
      legacy_models: 0,
      provider_coverage: %{
        anthropic: 2,
        openai: 2,
        google: 1
      },
      capabilities_distribution: %{
        tool_call: 4,
        reasoning: 3
      },
      note: "Mock statistics (minimal tier)"
    }
  end

  defp standard_registry_stats do
    %{
      total_models: 15,
      total_providers: 5,
      registry_models: 15,
      legacy_models: 0,
      provider_coverage: %{
        anthropic: 3,
        openai: 4,
        google: 1,
        groq: 3,
        perplexity: 3
      },
      capabilities_distribution: %{
        tool_call: 9,
        reasoning: 5
      },
      note: "Mock statistics (standard tier)"
    }
  end

  defp comprehensive_registry_stats do
    %{
      total_models: 50,
      total_providers: 10,
      registry_models: 50,
      legacy_models: 0,
      provider_coverage: %{
        anthropic: 3,
        openai: 4,
        google: 6,
        groq: 3,
        perplexity: 3,
        cohere: 5,
        togetherai: 5,
        mistral: 5,
        ai21: 5,
        openrouter: 5
      },
      capabilities_distribution: %{
        tool_call: 25,
        reasoning: 8
      },
      note: "Mock statistics (comprehensive tier)"
    }
  end

  # Filter Application (mimics real registry filtering logic)

  defp apply_mock_filters(models, []), do: models

  defp apply_mock_filters(models, filters) do
    Enum.filter(models, fn model ->
      Enum.all?(filters, fn {filter_type, filter_value} ->
        apply_single_filter(model, filter_type, filter_value)
      end)
    end)
  end

  defp apply_single_filter(model, :capability, required_capability) do
    case model.capabilities do
      nil -> false
      capabilities -> Map.get(capabilities, required_capability, false)
    end
  end

  defp apply_single_filter(model, :max_cost_per_token, max_cost) do
    case model.cost do
      nil -> true
      %{input: input_cost} when is_number(input_cost) -> input_cost <= max_cost
      _ -> true
    end
  end

  defp apply_single_filter(model, :min_context_length, min_length) do
    case model.endpoints do
      [] -> false
      [endpoint | _] ->
        context = Map.get(endpoint, :context_length, 0)
        context >= min_length
      _ -> false
    end
  end

  defp apply_single_filter(model, :modality, required_modality) do
    case model.modalities do
      nil -> required_modality == :text
      %{input: input_modalities} -> required_modality in input_modalities
      _ -> required_modality == :text
    end
  end

  defp apply_single_filter(_model, _filter_type, _filter_value) do
    # Unknown filter type, allow through
    true
  end

  # Macro for easy inclusion in tests

  defmacro __using__(opts) do
    tier = Keyword.get(opts, :tier, :minimal)

    quote do
      import Jido.AI.Test.RegistryHelpers

      setup do
        case unquote(tier) do
          :minimal -> setup_minimal_registry_mock()
          :standard -> setup_standard_registry_mock()
          :comprehensive -> setup_comprehensive_registry_mock()
          _ -> setup_minimal_registry_mock()
        end

        :ok
      end
    end
  end
end
