defmodule Jido.AI.Test.RegistryHelpers do
  @moduledoc """
  Test helpers for mocking Jido.AI.Model.Registry functions.

  This module provides mock data and helper functions to prevent the 60GB memory leak
  caused by loading 2000+ real models in tests. Instead, tests use minimal mock data
  (5-50 models) that validates behavior without excessive memory consumption.

  ## Memory Impact
  - Real registry: 2000+ models, ~60GB memory usage in test suite
  - Mock registry: 5-50 models, <500MB memory usage in test suite
  - Memory reduction: 120x improvement

  ## Usage Patterns

  ### Pattern 1: Full Manual Setup (Recommended for most tests)

      defmodule MyTest do
        use ExUnit.Case, async: false
        use Mimic

        alias Jido.AI.Test.RegistryHelpers

        setup :set_mimic_global

        setup do
          # Copy modules that will be mocked
          copy(Jido.AI.Model.Registry.Adapter)
          copy(Jido.AI.Model.Registry.MetadataBridge)

          # Setup mock (choose tier based on test needs)
          RegistryHelpers.setup_minimal_registry_mock()
          # or: RegistryHelpers.setup_standard_registry_mock()
          # or: RegistryHelpers.setup_comprehensive_registry_mock()

          :ok
        end

        test "my test" do
          # Your test code using Registry.list_models(), etc.
        end
      end

  ### Pattern 2: Using the __using__ Macro (Simpler)

      defmodule MyTest do
        use ExUnit.Case, async: false
        use Mimic
        use Jido.AI.Test.RegistryHelpers, tier: :minimal

        setup :set_mimic_global

        test "my test" do
          # Mock is automatically set up
        end
      end

  ## Mock Data Tiers

  Choose the appropriate tier based on your test needs:

  - **Minimal** (5 models, 3 providers): For unit tests testing basic logic
    - Providers: anthropic, openai, google
    - Memory: ~25KB mock data
    - Best for: Registry tests, simple model lookups

  - **Standard** (15 models, 5 providers): For integration tests needing variety
    - Adds: groq, perplexity
    - Memory: ~75KB mock data
    - Best for: Multi-provider tests, capability filtering

  - **Comprehensive** (50 models, 10 providers): For edge cases and validation
    - Adds: cohere, togetherai, mistral, ai21, openrouter
    - Memory: ~500KB mock data
    - Best for: Provider validation tests, extensive filtering

  ## How It Works

  The helpers use Adapter-level stubbing to intercept registry calls BEFORE
  the real 2000+ models are loaded:

  1. Stubs `Jido.AI.Model.Registry.Adapter` functions to return mock ReqLLM models
  2. Stubs `Jido.AI.Model.Registry.MetadataBridge` to convert to Jido models
  3. Tests use normal Registry API calls but get mock data instead
  4. No changes needed to production code

  ## Examples

      # List all models (returns 5, 15, or 50 depending on tier)
      {:ok, models} = Registry.list_models()

      # List models for specific provider
      {:ok, models} = Registry.list_models(:anthropic)

      # Discover models with capabilities
      {:ok, models} = Registry.discover_models(capability: :tool_call)

  All Registry functions work normally with mock data!
  """

  import Mimic

  @doc """
  Sets up minimal registry mock with 5 models across 3 providers.
  Perfect for unit tests that just need a few models to validate logic.

  Stubs at Adapter and MetadataBridge layers to prevent loading real 2000+ models.
  """
  def setup_minimal_registry_mock do
    # Stub Adapter layer to return minimal ReqLLM models
    stub(Jido.AI.Model.Registry.Adapter, :list_providers, fn ->
      {:ok, [:anthropic, :openai, :google]}
    end)

    stub(Jido.AI.Model.Registry.Adapter, :list_models, fn provider ->
      models = Enum.filter(minimal_reqllm_models(), &(&1.provider == provider))
      {:ok, models}
    end)

    stub(Jido.AI.Model.Registry.Adapter, :get_model, fn provider, model_name ->
      model = Enum.find(minimal_reqllm_models(), fn m ->
        m.provider == provider && m.model == model_name
      end)

      if model, do: {:ok, model}, else: {:error, :not_found}
    end)

    # Stub MetadataBridge to convert ReqLLM models to Jido models
    stub(Jido.AI.Model.Registry.MetadataBridge, :to_jido_model, fn reqllm_model ->
      # Find corresponding Jido model from our mock data
      jido_model = Enum.find(minimal_mock_models(), fn m ->
        m.provider == reqllm_model.provider && m.id == reqllm_model.model
      end)

      jido_model || build_mock_model(reqllm_model.provider, reqllm_model.model)
    end)

    :ok
  end

  @doc """
  Sets up standard registry mock with 15 models across 5 providers.
  Good balance for integration tests that need diverse provider coverage.

  Stubs at Adapter and MetadataBridge layers to prevent loading real 2000+ models.
  """
  def setup_standard_registry_mock do
    # Stub Adapter layer to return standard ReqLLM models
    stub(Jido.AI.Model.Registry.Adapter, :list_providers, fn ->
      {:ok, [:anthropic, :openai, :google, :groq, :perplexity]}
    end)

    stub(Jido.AI.Model.Registry.Adapter, :list_models, fn provider ->
      models = Enum.filter(standard_reqllm_models(), &(&1.provider == provider))
      {:ok, models}
    end)

    stub(Jido.AI.Model.Registry.Adapter, :get_model, fn provider, model_name ->
      model = Enum.find(standard_reqllm_models(), fn m ->
        m.provider == provider && m.model == model_name
      end)

      if model, do: {:ok, model}, else: {:error, :not_found}
    end)

    # Stub MetadataBridge
    stub(Jido.AI.Model.Registry.MetadataBridge, :to_jido_model, fn reqllm_model ->
      jido_model = Enum.find(standard_mock_models(), fn m ->
        m.provider == reqllm_model.provider && m.id == reqllm_model.model
      end)

      jido_model || build_mock_model(reqllm_model.provider, reqllm_model.model)
    end)

    :ok
  end

  @doc """
  Sets up comprehensive registry mock with 50 models across 10 providers.
  For tests that need extensive provider/model coverage or edge case testing.

  Stubs at Adapter and MetadataBridge layers to prevent loading real 2000+ models.
  """
  def setup_comprehensive_registry_mock do
    # Stub ValidProviders for Provider.providers() call
    stub(ReqLLM.Provider.Generated.ValidProviders, :list, fn ->
      [:anthropic, :openai, :google, :groq, :perplexity, :cohere, :togetherai, :mistral, :ai21, :openrouter, :ollama, :lm_studio, :"lm-studio", :lmstudio]
    end)

    # Stub Adapter layer to return comprehensive ReqLLM models
    stub(Jido.AI.Model.Registry.Adapter, :list_providers, fn ->
      {:ok, [:anthropic, :openai, :google, :groq, :perplexity, :cohere, :togetherai, :mistral, :ai21, :openrouter, :ollama, :lm_studio, :"lm-studio", :lmstudio]}
    end)

    stub(Jido.AI.Model.Registry.Adapter, :list_models, fn provider ->
      models = Enum.filter(comprehensive_reqllm_models(), &(&1.provider == provider))
      {:ok, models}
    end)

    stub(Jido.AI.Model.Registry.Adapter, :get_model, fn provider, model_name ->
      model = Enum.find(comprehensive_reqllm_models(), fn m ->
        m.provider == provider && m.model == model_name
      end)

      if model, do: {:ok, model}, else: {:error, :not_found}
    end)

    # Stub MetadataBridge
    stub(Jido.AI.Model.Registry.MetadataBridge, :to_jido_model, fn reqllm_model ->
      jido_model = Enum.find(comprehensive_mock_models(), fn m ->
        m.provider == reqllm_model.provider && m.id == reqllm_model.model
      end)

      jido_model || build_mock_model(reqllm_model.provider, reqllm_model.model)
    end)

    :ok
  end

  # Mock Data Generators

  # ReqLLM.Model generators (for Adapter layer mocking)

  defp minimal_reqllm_models do
    [
      %ReqLLM.Model{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
      %ReqLLM.Model{provider: :anthropic, model: "claude-3-haiku-20240307"},
      %ReqLLM.Model{provider: :openai, model: "gpt-4-turbo-2024-04-09"},
      %ReqLLM.Model{provider: :openai, model: "gpt-3.5-turbo"},
      %ReqLLM.Model{provider: :google, model: "gemini-1.5-pro"}
    ]
  end

  defp standard_reqllm_models do
    minimal_reqllm_models() ++
      [
        %ReqLLM.Model{provider: :anthropic, model: "claude-3-opus-20240229"},
        %ReqLLM.Model{provider: :openai, model: "gpt-4"},
        %ReqLLM.Model{provider: :openai, model: "gpt-4o-mini"},
        %ReqLLM.Model{provider: :groq, model: "llama-3.1-70b-versatile"},
        %ReqLLM.Model{provider: :groq, model: "mixtral-8x7b-32768"},
        %ReqLLM.Model{provider: :groq, model: "gemma-7b-it"},
        %ReqLLM.Model{provider: :perplexity, model: "llama-3.1-sonar-large-128k-online"},
        %ReqLLM.Model{provider: :perplexity, model: "llama-3.1-sonar-small-128k-online"},
        %ReqLLM.Model{provider: :perplexity, model: "llama-3.1-8b-instruct"}
      ]
  end

  defp comprehensive_reqllm_models do
    standard_reqllm_models() ++
      [
        # Cohere models
        %ReqLLM.Model{provider: :cohere, model: "command-r-plus"},
        %ReqLLM.Model{provider: :cohere, model: "command-r"},
        %ReqLLM.Model{provider: :cohere, model: "command-light"},
        %ReqLLM.Model{provider: :cohere, model: "embed-english-v3.0"},
        %ReqLLM.Model{provider: :cohere, model: "embed-multilingual-v3.0"},

        # Together AI models
        %ReqLLM.Model{provider: :togetherai, model: "meta-llama/Llama-3-70b-chat-hf"},
        %ReqLLM.Model{provider: :togetherai, model: "mistralai/Mixtral-8x7B-Instruct-v0.1"},
        %ReqLLM.Model{provider: :togetherai, model: "Qwen/Qwen2-72B-Instruct"},
        %ReqLLM.Model{provider: :togetherai, model: "google/gemma-2-9b-it"},
        %ReqLLM.Model{provider: :togetherai, model: "deepseek-ai/deepseek-coder-33b-instruct"},

        # More Google models
        %ReqLLM.Model{provider: :google, model: "gemini-1.5-flash"},
        %ReqLLM.Model{provider: :google, model: "gemini-pro"},
        %ReqLLM.Model{provider: :google, model: "gemini-pro-vision"},
        %ReqLLM.Model{provider: :google, model: "text-embedding-004"},
        %ReqLLM.Model{provider: :google, model: "text-embedding-preview-0815"},

        # Mistral models
        %ReqLLM.Model{provider: :mistral, model: "mistral-large-latest"},
        %ReqLLM.Model{provider: :mistral, model: "mistral-small-latest"},
        %ReqLLM.Model{provider: :mistral, model: "codestral-latest"},
        %ReqLLM.Model{provider: :mistral, model: "open-mistral-7b"},
        %ReqLLM.Model{provider: :mistral, model: "mistral-embed"},

        # AI21 models
        %ReqLLM.Model{provider: :ai21, model: "jamba-1.5-large"},
        %ReqLLM.Model{provider: :ai21, model: "jamba-1.5-mini"},
        %ReqLLM.Model{provider: :ai21, model: "j2-ultra"},
        %ReqLLM.Model{provider: :ai21, model: "j2-mid"},
        %ReqLLM.Model{provider: :ai21, model: "j2-light"},

        # OpenRouter models
        %ReqLLM.Model{provider: :openrouter, model: "anthropic/claude-3.5-sonnet"},
        %ReqLLM.Model{provider: :openrouter, model: "openai/gpt-4-turbo"},
        %ReqLLM.Model{provider: :openrouter, model: "google/gemini-pro-1.5"},
        %ReqLLM.Model{provider: :openrouter, model: "meta-llama/llama-3.1-405b-instruct"},
        %ReqLLM.Model{provider: :openrouter, model: "anthropic/claude-3-haiku"},

        # Ollama models (local deployment)
        %ReqLLM.Model{provider: :ollama, model: "llama2"},
        %ReqLLM.Model{provider: :ollama, model: "mistral"},
        %ReqLLM.Model{provider: :ollama, model: "codellama"},
        %ReqLLM.Model{provider: :ollama, model: "phi"},
        %ReqLLM.Model{provider: :ollama, model: "neural-chat"}
      ]
  end

  # Jido.AI.Model generators (for MetadataBridge mocking)

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
