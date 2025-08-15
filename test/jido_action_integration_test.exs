defmodule Jido.AI.JidoActionIntegrationTest do
  @moduledoc """
  Comprehensive test suite for Jido Action integration with jido_ai.

  Tests the seamless integration between jido_ai LLM capabilities 
  and jido_action tool system for function calling.
  """

  use ExUnit.Case
  use Jido.AI.TestSupport.HTTPCase

  import Jido.AI.Messages

  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.{ContentPart, Message}
  alias Jido.Tools.Arithmetic.Add
  alias Jido.Tools.Arithmetic.Divide
  alias Jido.Tools.Weather

  setup do
    # Register providers for testing
    Jido.AI.Provider.Registry.register(:openai, OpenAI)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "action to tool conversion" do
    test "converts arithmetic action to valid tool definition" do
      tool_def = Add.to_tool()

      assert tool_def.name == "add"
      assert tool_def.description == "Adds two numbers"
      assert is_function(tool_def.function, 2)

      schema = tool_def.parameters_schema
      assert schema[:type] == "object"
      assert schema[:required] == ["value", "amount"]

      properties = schema[:properties]
      assert properties["value"][:type] == "integer"
      assert properties["amount"][:type] == "integer"
    end

    test "executes arithmetic action through tool interface" do
      tool_def = Add.to_tool()

      params = %{
        "value" => 10,
        "amount" => 5
      }

      assert {:ok, result_json} = tool_def.function.(params, %{})
      result = Jason.decode!(result_json)

      assert result["result"] == 15
    end

    test "handles action execution errors through tool interface" do
      tool_def = Divide.to_tool()

      params = %{
        "value" => 10,
        "amount" => 0
      }

      assert {:error, error_json} = tool_def.function.(params, %{})
      error = Jason.decode!(error_json)

      assert error["error"] =~ "Cannot divide by zero"
    end
  end

  describe "AI tool calling with actions" do
    test "simulates complete AI workflow with actions as tools" do
      # Simulate an AI request to use arithmetic
      user_message = user("Add 10 and 5")

      # Mock AI deciding to use add tool
      tool_call =
        ContentPart.tool_call(
          "add_001",
          "add",
          %{value: 10, amount: 5}
        )

      assistant_message =
        Message.assistant_with_tools(
          "I'll calculate that for you.",
          [tool_call]
        )

      # Execute the action through tool interface
      tool_def = Add.to_tool()

      params = %{
        "value" => 10,
        "amount" => 5
      }

      assert {:ok, result_json} = tool_def.function.(params, %{})
      result = Jason.decode!(result_json)

      # Create tool result message
      tool_result_message =
        Message.tool_result(
          "add_001",
          "add",
          result
        )

      # Final AI response
      final_message = assistant("The result of 10 + 5 is #{result["result"]}.")

      conversation = [user_message, assistant_message, tool_result_message, final_message]
      assert Enum.all?(conversation, &Message.valid?/1)

      # Verify tool call linking - check the second content part (first is text)
      tool_call_part = Enum.find(assistant_message.content, &(&1.type == :tool_call))
      assert tool_call_part.tool_call_id == "add_001"
      assert tool_result_message.tool_call_id == "add_001"
    end

    test "multiple actions as tools in single conversation" do
      user_message = user("Add 10 and 5, and get weather for NYC")

      # AI makes multiple tool calls
      tool_calls = [
        ContentPart.tool_call("add_001", "add", %{value: 10, amount: 5}),
        ContentPart.tool_call("weather_001", "weather", %{location: "NYC", test: true, format: "map"})
      ]

      assistant_message =
        Message.assistant_with_tools(
          "I'll calculate that and check the weather for you.",
          tool_calls
        )

      # Execute both actions
      add_tool = Add.to_tool()
      weather_tool = Weather.to_tool()

      {:ok, add_result_json} =
        add_tool.function.(
          %{
            "value" => 10,
            "amount" => 5
          },
          %{}
        )

      {:ok, weather_result_json} =
        weather_tool.function.(
          %{
            "location" => "NYC",
            "test" => true,
            "format" => "map"
          },
          %{}
        )

      add_result = Jason.decode!(add_result_json)
      weather_result = Jason.decode!(weather_result_json)

      # Create tool result messages
      add_result_msg = Message.tool_result("add_001", "add", add_result)
      weather_result_msg = Message.tool_result("weather_001", "weather", weather_result)

      final_message = assistant("10 + 5 = #{add_result["result"]}. Weather information retrieved for NYC.")

      conversation = [
        user_message,
        assistant_message,
        add_result_msg,
        weather_result_msg,
        final_message
      ]

      assert Enum.all?(conversation, &Message.valid?/1)
    end
  end

  describe "provider tool integration" do
    test "converts actions to OpenAI-compatible tool format" do
      actions = [Add, Weather]

      # Convert to OpenAI tool format
      openai_tools =
        Enum.map(actions, fn action ->
          tool_def = action.to_tool()

          %{
            "type" => "function",
            "function" => %{
              "name" => tool_def.name,
              "description" => tool_def.description,
              "parameters" => tool_def.parameters_schema
            }
          }
        end)

      assert length(openai_tools) == 2

      add_tool = Enum.find(openai_tools, &(&1["function"]["name"] == "add"))
      weather_tool = Enum.find(openai_tools, &(&1["function"]["name"] == "weather"))

      assert add_tool["type"] == "function"
      assert add_tool["function"]["description"] =~ "Adds two numbers"

      assert weather_tool["type"] == "function"
      assert weather_tool["function"]["description"] =~ "weather"
      # Note: required fields are checked in the detailed integration test
    end
  end

  describe "new API integration test" do
    test "generate_text with actions option", %{test_name: test_name} do
      # Mock successful OpenAI response with tool call
      with_success(%{
        choices: [
          %{
            message: %{
              content: "I'll add those numbers for you.",
              tool_calls: [
                %{
                  id: "call_123",
                  type: "function",
                  function: %{
                    name: "add",
                    arguments: Jason.encode!(%{value: 10, amount: 5})
                  }
                }
              ]
            }
          }
        ]
      }) do
        # Test new API - actions passed via opts
        result =
          Jido.AI.generate_text(
            "openai:gpt-4o",
            "What is 10 + 5?",
            actions: [Add]
          )

        # This tests that the integration works at the API level
        # The mock ensures we get the expected response structure
        assert {:ok, response} = result
        assert is_binary(response)
      end
    end

    test "generate_text with tools option", %{test_name: test_name} do
      custom_tool = %{
        "type" => "function",
        "function" => %{
          "name" => "custom_add",
          "description" => "Custom addition function",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "a" => %{"type" => "number"},
              "b" => %{"type" => "number"}
            },
            "required" => ["a", "b"]
          }
        }
      }

      with_success(%{
        choices: [%{message: %{content: "I'll use the custom tool."}}]
      }) do
        result =
          Jido.AI.generate_text(
            "openai:gpt-4o",
            "Use the custom add function",
            tools: [custom_tool]
          )

        assert {:ok, response} = result
        assert is_binary(response)
      end
    end

    test "stream_text with actions option", %{test_name: test_name} do
      with_sse([
        %{choices: [%{delta: %{content: "Calculating"}}]},
        %{choices: [%{delta: %{content: " result..."}}]}
      ]) do
        result =
          Jido.AI.stream_text(
            "openai:gpt-4o",
            "What is 10 + 5?",
            actions: [Add]
          )

        assert {:ok, stream} = result
        chunks = Enum.to_list(stream)
        result_text = IO.iodata_to_binary(chunks)
        assert is_binary(result_text)
        assert String.length(result_text) > 0
      end
    end
  end

  describe "helper functions for seamless integration" do
    test "batch converts actions to tool definitions" do
      actions = [Add, Weather]

      # This function should exist in jido_ai for seamless integration
      tool_definitions =
        Enum.map(actions, fn action ->
          tool_def = action.to_tool()

          %{
            "type" => "function",
            "function" => %{
              "name" => tool_def.name,
              "description" => tool_def.description,
              "parameters" => tool_def.parameters_schema
            }
          }
        end)

      assert length(tool_definitions) == 2
      assert Enum.all?(tool_definitions, &(&1["type"] == "function"))
    end

    test "helper to execute tool calls with actions" do
      # This tests what should be a helper function in jido_ai
      actions = [Add, Weather]
      action_map = Map.new(actions, &{&1.name(), &1})

      # Mock tool call from AI
      tool_call = %{
        "id" => "add_001",
        "function" => %{
          "name" => "add",
          "arguments" => Jason.encode!(%{value: 5, amount: 3})
        }
      }

      # Execute tool call
      function_name = tool_call["function"]["name"]
      {:ok, arguments} = Jason.decode(tool_call["function"]["arguments"])

      action = Map.get(action_map, function_name)
      assert action == Add

      tool_def = action.to_tool()
      assert {:ok, result_json} = tool_def.function.(arguments, %{})
      result = Jason.decode!(result_json)

      assert result["result"] == 8
    end
  end
end
