defmodule Jido.AI.CostCalculatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{CostCalculator, Model}

  describe "calculate_cost/3" do
    test "calculates cost with valid model pricing" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        cost: %{input: 1.5, output: 6.0}
      }

      cost = CostCalculator.calculate_cost(model, 1000, 500)

      assert cost.input_tokens == 1000
      assert cost.output_tokens == 500
      assert cost.input_cost == 0.0015
      assert cost.output_cost == 0.003
      assert_in_delta cost.total_cost, 0.0045, 0.00001
      assert cost.currency == "USD"
    end

    test "returns nil for model without cost data" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        cost: nil
      }

      assert CostCalculator.calculate_cost(model, 1000, 500) == nil
    end

    test "handles zero tokens" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        cost: %{input: 1.5, output: 6.0}
      }

      cost = CostCalculator.calculate_cost(model, 0, 0)

      assert cost.input_tokens == 0
      assert cost.output_tokens == 0
      assert cost.total_cost == 0.0
    end
  end

  describe "calculate_request_cost/3" do
    test "calculates cost for request and response" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        cost: %{input: 1.5, output: 6.0}
      }

      request = %{
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "user", "content" => "Hello world"}
        ]
      }

      response = %{
        "choices" => [
          %{"message" => %{"content" => "Hi there!"}}
        ]
      }

      cost = CostCalculator.calculate_request_cost(model, request, response)

      assert cost != nil
      assert cost.input_tokens > 0
      assert cost.output_tokens > 0
      assert cost.total_cost > 0.0
    end
  end

  describe "format_cost/1" do
    test "formats cost breakdown" do
      cost = %{
        input_tokens: 1000,
        output_tokens: 500,
        input_cost: 0.0015,
        output_cost: 0.003,
        total_cost: 0.0045,
        currency: "USD"
      }

      formatted = CostCalculator.format_cost(cost)
      assert formatted =~ "$0.0045"
      assert formatted =~ "1000 in"
      assert formatted =~ "500 out"
    end

    test "handles nil cost" do
      assert CostCalculator.format_cost(nil) == "Cost unavailable"
    end
  end

  describe "get_model_rates/1" do
    test "returns rates for model with cost data" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        cost: %{input: 1.5, output: 6.0}
      }

      assert CostCalculator.get_model_rates(model) == {1.5, 6.0}
    end

    test "returns nil for model without cost data" do
      model = %Model{
        provider: :openai,
        model: "gpt-4",
        cost: nil
      }

      assert CostCalculator.get_model_rates(model) == nil
    end
  end
end
