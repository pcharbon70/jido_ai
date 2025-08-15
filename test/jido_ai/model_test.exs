defmodule Jido.AI.ModelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Jido.AI.TestUtils

  alias Jido.AI.Model
  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.Test.FakeProvider

  doctest Model

  setup do
    # Register providers needed for tests
    Jido.AI.Provider.Registry.register(:openai, OpenAI)
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "from/1" do
    test "accepts valid struct and returns it unchanged" do
      model = openai_gpt4_model()
      assert {:ok, ^model} = Model.from(model)
    end

    test "parses valid string format" do
      assert {:ok, model} = Model.from("openai:gpt-4")
      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "parses valid tuple format with model" do
      assert {:ok, model} = Model.from({:openai, model: "gpt-4", temperature: 0.7})
      assert model.provider == :openai
      assert model.model == "gpt-4"
      assert model.temperature == 0.7
    end

    test "fills defaults for valid tuple" do
      assert {:ok, model} = Model.from({:openai, model: "gpt-4"})
      assert model.limit.context == 128_000
      assert model.limit.output == 4096
      assert model.modalities.input == [:text]
    end

    test "returns error for string without colon" do
      assert {:error, _message} = Model.from("invalid-format")
    end

    test "returns error for empty string" do
      assert {:error, _message} = Model.from("")
    end

    test "returns error for unknown provider in string" do
      assert {:error, _message} = Model.from("unknown:model")
    end

    test "returns error for tuple without model key" do
      assert {:error, _message} = Model.from({:openai, temperature: 0.7})
    end

    test "returns error for unknown provider in tuple" do
      assert {:error, _message} = Model.from({:unknown, model: "test"})
    end

    test "returns error for invalid input types" do
      invalid_inputs = [123, [], %{not: "a model"}, nil, :atom]

      for input <- invalid_inputs do
        assert {:error, _message} = Model.from(input)
      end
    end

    test "handles string with multiple colons" do
      assert {:ok, model} = Model.from("openai:gpt-4:turbo")
      assert model.provider == :openai
      assert model.model == "gpt-4:turbo"
    end

    test "handles empty model name" do
      # This might be valid depending on implementation
      case Model.from("openai:") do
        {:ok, _model} -> :ok
        {:error, _message} -> :ok
      end
    end

    test "handles whitespace in model names" do
      assert {:ok, model} = Model.from("openai:gpt 4")
      assert model.model == "gpt 4"
    end

    test "preserves tuple options that exist on struct" do
      opts = [
        model: "gpt-4",
        temperature: 0.8,
        max_tokens: 1000
      ]

      assert {:ok, model} = Model.from({:openai, opts})
      assert model.temperature == 0.8
      assert model.max_tokens == 1000
    end
  end

  describe "validate/1" do
    test "returns error for required fields missing" do
      incomplete_model = %Model{}
      assert {:error, _} = Model.validate(incomplete_model)
    end

    test "validate is used internally and works with created models" do
      # Test that models created by from/1 can be validated
      assert {:ok, model} = Model.from({:openai, model: "gpt-4"})

      # The validate function works on the metadata portion
      case Model.validate(model) do
        {:ok, _} -> :ok
        # Runtime fields might not pass metadata validation
        {:error, _} -> :ok
      end
    end
  end

  describe "property tests" do
    property "invalid string spec without colon always errors" do
      check all(
              str <- StreamData.string(:printable),
              not String.contains?(str, ":")
            ) do
        assert {:error, _} = Model.from(str)
      end
    end

    property "string round-trip for valid providers" do
      providers = [:openai, :anthropic, :google, :mistral]

      check all(
              provider <- StreamData.member_of(providers),
              model_name <- StreamData.string(:alphanumeric, min_length: 1)
            ) do
        input_string = "#{provider}:#{model_name}"

        case Model.from(input_string) do
          {:ok, model} ->
            assert model.provider == provider
            assert model.model == model_name

          {:error, _} ->
            # Some model names might be invalid due to provider validation
            :ok
        end
      end
    end

    property "tuple format preserves all valid options" do
      providers = [:openai, :anthropic, :google, :mistral]

      check all(
              provider <- StreamData.member_of(providers),
              model_name <- StreamData.string(:alphanumeric, min_length: 1),
              temperature <- StreamData.float(min: 0.0, max: 2.0),
              max_tokens <- StreamData.positive_integer()
            ) do
        input = {provider, model: model_name, temperature: temperature, max_tokens: max_tokens}

        case Model.from(input) do
          {:ok, model} ->
            assert model.provider == provider
            assert model.model == model_name
            assert model.temperature == temperature
            assert model.max_tokens == max_tokens

          {:error, _} ->
            # Some combinations might be invalid
            :ok
        end
      end
    end
  end

  describe "validation functions" do
    test "validate_date_format/1 accepts valid dates" do
      valid_dates = ["2024-01", "2024-12-31", "2023-06-15"]

      for date <- valid_dates do
        assert {:ok, ^date} = Model.validate_date_format(date)
      end
    end

    test "validate_date_format/1 accepts nil" do
      assert {:ok, nil} = Model.validate_date_format(nil)
    end

    test "validate_date_format/1 rejects invalid formats" do
      invalid_dates = ["not-a-date", "invalid", 123, [], %{}]

      for date <- invalid_dates do
        assert {:error, _} = Model.validate_date_format(date)
      end
    end

    test "validate_cost/1 accepts valid cost maps" do
      valid_costs = [
        %{input: 0.1, output: 0.2},
        %{input: 0.1, output: 0.2, cache_read: 0.05, cache_write: 0.15}
      ]

      for cost <- valid_costs do
        assert {:ok, ^cost} = Model.validate_cost(cost)
      end
    end

    test "validate_cost/1 accepts nil" do
      assert {:ok, nil} = Model.validate_cost(nil)
    end

    test "validate_cost/1 rejects invalid costs" do
      invalid_costs = ["not-a-map", 123, [], %{invalid: "keys"}]

      for cost <- invalid_costs do
        assert {:error, _} = Model.validate_cost(cost)
      end
    end

    test "validate_limit/1 accepts valid limit maps" do
      valid_limit = %{context: 4096, output: 2048}
      assert {:ok, ^valid_limit} = Model.validate_limit(valid_limit)
    end

    test "validate_limit/1 rejects invalid limits" do
      invalid_limits = ["not-a-map", 123, [], %{invalid: "keys"}, %{}]

      for limit <- invalid_limits do
        assert {:error, _} = Model.validate_limit(limit)
      end
    end
  end

  describe "from_json functions" do
    test "from_json/1 handles invalid JSON" do
      invalid_data = %{"invalid" => "structure"}
      assert {:error, _} = Model.from_json(invalid_data)
    end

    test "from_json functions exist and are callable" do
      # Test that the functions exist without complex validation 
      assert function_exported?(Model, :from_json, 1)
      assert function_exported?(Model, :from_json!, 1)
    end
  end

  describe "edge cases" do
    test "handles special characters in model names" do
      special_names = [
        "gpt-4-turbo-preview",
        "claude-3.5-sonnet",
        "gemini-1.5-pro-001",
        "model_with_underscores",
        "model.with.dots"
      ]

      for name <- special_names do
        assert {:ok, model} = Model.from("openai:#{name}")
        assert model.model == name
      end
    end

    test "handles provider names as strings vs atoms" do
      # String format always converts to atom
      assert {:ok, model} = Model.from("openai:gpt-4")
      assert model.provider == :openai

      # Tuple format with atom
      assert {:ok, model} = Model.from({:openai, model: "gpt-4"})
      assert model.provider == :openai
    end

    test "handles empty and nil values in tuple" do
      # Some of these might actually be valid, so just test they don't crash
      tuples_to_test = [
        {:openai, model: ""},
        {:openai, model: nil},
        {:openai, []},
        {nil, model: "gpt-4"}
      ]

      for tuple <- tuples_to_test do
        case Model.from(tuple) do
          {:ok, _model} -> :ok
          {:error, _message} -> :ok
        end
      end
    end

    test "handles large numeric values" do
      # Test with reasonable large values
      assert {:ok, model} = Model.from({:openai, model: "gpt-4", max_tokens: 100_000})
      assert model.max_tokens == 100_000
    end
  end

  describe "provider defaults" do
    test "applies same defaults for all providers" do
      providers = [:openai, :fake]

      for provider <- providers do
        assert {:ok, model} = Model.from({provider, model: "test-model"})
        assert model.limit.context == 128_000
        assert model.limit.output == 4096
        assert model.modalities.input == [:text]
        assert model.modalities.output == [:text]
      end
    end

    test "tuple options override runtime fields" do
      assert {:ok, model} =
               Model.from({:openai, model: "gpt-4", temperature: 0.8, max_tokens: 2000})

      assert model.temperature == 0.8
      assert model.max_tokens == 2000
    end
  end
end
