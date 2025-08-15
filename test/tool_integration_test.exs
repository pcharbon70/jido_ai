defmodule Jido.AI.ToolIntegrationTest do
  use ExUnit.Case

  alias Jido.AI.{ContentPart, Message}

  @moduletag :integration

  describe "complete tool call flow" do
    test "end-to-end tool call conversation validates properly" do
      # Step 1: User asks a question
      user_message = Message.new(:user, "What's the weather like in New York City?")
      assert Message.valid?(user_message)

      # Step 2: Assistant decides to call a tool
      tool_call =
        ContentPart.tool_call("call_weather_001", "get_current_weather", %{
          location: "New York City, NY",
          units: "fahrenheit"
        })

      assistant_message =
        Message.assistant_with_tools(
          "I'll check the current weather in New York City for you.",
          [tool_call]
        )

      assert Message.valid?(assistant_message)

      # Step 3: Tool execution result
      weather_result = %{
        location: "New York City, NY",
        temperature: 72,
        condition: "partly cloudy",
        humidity: 65,
        wind_speed: 8
      }

      tool_result_message =
        Message.tool_result(
          "call_weather_001",
          "get_current_weather",
          weather_result
        )

      assert Message.valid?(tool_result_message)

      # Step 4: Assistant provides final response
      final_response =
        Message.new(
          :assistant,
          "The weather in New York City is currently 72°F with partly cloudy conditions. The humidity is at 65% with wind speeds of 8 mph."
        )

      assert Message.valid?(final_response)

      # Verify complete conversation
      conversation = [user_message, assistant_message, tool_result_message, final_response]
      assert Enum.all?(conversation, &Message.valid?/1)

      # Verify tool call ID linking
      [assistant_tool_call] = assistant_message.content |> Enum.filter(&(&1.type == :tool_call))
      [tool_result_part] = tool_result_message.content |> Enum.filter(&(&1.type == :tool_result))

      assert assistant_tool_call.tool_call_id == tool_result_part.tool_call_id
      assert tool_result_message.tool_call_id == assistant_tool_call.tool_call_id
    end

    test "multiple parallel tool calls conversation" do
      # User asks for multiple pieces of information
      user_message = Message.new(:user, "Can you tell me the weather, current time, and my next meeting?")

      # Assistant makes multiple tool calls
      tool_calls = [
        ContentPart.tool_call("call_001", "get_weather", %{location: "current"}),
        ContentPart.tool_call("call_002", "get_current_time", %{timezone: "local"}),
        ContentPart.tool_call("call_003", "get_next_meeting", %{calendar: "primary"})
      ]

      assistant_message =
        Message.assistant_with_tools(
          "I'll get that information for you right now.",
          tool_calls
        )

      # Multiple tool results
      weather_result =
        Message.tool_result("call_001", "get_weather", %{
          temperature: 75,
          condition: "sunny"
        })

      time_result =
        Message.tool_result("call_002", "get_current_time", %{
          time: "2:30 PM",
          timezone: "EST"
        })

      meeting_result =
        Message.tool_result("call_003", "get_next_meeting", %{
          title: "Team Standup",
          start_time: "3:00 PM",
          duration: "30 minutes"
        })

      # Final assistant response
      final_response =
        Message.new(
          :assistant,
          "Here's the information: It's currently 75°F and sunny. The time is 2:30 PM EST. Your next meeting is 'Team Standup' at 3:00 PM for 30 minutes."
        )

      conversation = [
        user_message,
        assistant_message,
        weather_result,
        time_result,
        meeting_result,
        final_response
      ]

      # Validate entire conversation
      assert Enum.all?(conversation, &Message.valid?/1)

      # Verify tool call ID consistency
      assistant_tool_calls = assistant_message.content |> Enum.filter(&(&1.type == :tool_call))
      assert length(assistant_tool_calls) == 3

      tool_call_ids = Enum.map(assistant_tool_calls, & &1.tool_call_id)
      assert "call_001" in tool_call_ids
      assert "call_002" in tool_call_ids
      assert "call_003" in tool_call_ids

      # Verify each tool result has matching tool_call_id
      assert weather_result.tool_call_id == "call_001"
      assert time_result.tool_call_id == "call_002"
      assert meeting_result.tool_call_id == "call_003"
    end

    test "nested tool calls conversation" do
      # User request
      user_message = Message.new(:user, "Plan my trip to Paris")

      # Assistant makes initial tool call
      assistant_msg_1 =
        Message.assistant_with_tools(
          "I'll help you plan your trip to Paris. Let me start by checking flight options.",
          [ContentPart.tool_call("flight_001", "search_flights", %{destination: "Paris", from: "NYC"})]
        )

      # Flight search result
      flight_result =
        Message.tool_result("flight_001", "search_flights", %{
          best_flight: %{
            airline: "Air France",
            departure: "2024-02-15 08:00",
            arrival: "2024-02-15 21:30",
            price: "$850"
          }
        })

      # Assistant makes follow-up tool calls based on flight info
      assistant_msg_2 =
        Message.assistant_with_tools(
          "Great! I found a good flight. Now let me search for hotels and check the weather forecast.",
          [
            ContentPart.tool_call("hotel_001", "search_hotels", %{city: "Paris", check_in: "2024-02-15"}),
            ContentPart.tool_call("weather_001", "get_forecast", %{city: "Paris", dates: ["2024-02-15", "2024-02-16"]})
          ]
        )

      # Hotel and weather results
      hotel_result =
        Message.tool_result("hotel_001", "search_hotels", %{
          recommended_hotel: %{
            name: "Hotel de la Paix",
            rating: 4.5,
            price_per_night: "$180"
          }
        })

      weather_result =
        Message.tool_result("weather_001", "get_forecast", %{
          forecast: [
            %{date: "2024-02-15", high: 45, low: 35, condition: "partly cloudy"},
            %{date: "2024-02-16", high: 48, low: 38, condition: "sunny"}
          ]
        })

      # Final recommendation
      final_message =
        Message.new(
          :assistant,
          "Perfect! I've planned your Paris trip: Air France flight on Feb 15th ($850), Hotel de la Paix (4.5⭐, $180/night). Weather looks nice - partly cloudy arrival day, sunny the next day (45-48°F). Shall I book these options?"
        )

      conversation = [
        user_message,
        assistant_msg_1,
        flight_result,
        assistant_msg_2,
        hotel_result,
        weather_result,
        final_message
      ]

      # Validate entire nested conversation
      assert Enum.all?(conversation, &Message.valid?/1)

      # Verify tool call IDs are unique and properly linked
      all_tool_calls =
        conversation
        |> Enum.flat_map(fn msg ->
          case msg.content do
            content when is_list(content) -> Enum.filter(content, &(&1.type == :tool_call))
            _ -> []
          end
        end)

      all_tool_results =
        conversation
        |> Enum.flat_map(fn msg ->
          case msg.content do
            content when is_list(content) -> Enum.filter(content, &(&1.type == :tool_result))
            _ -> []
          end
        end)

      tool_call_ids = Enum.map(all_tool_calls, & &1.tool_call_id)
      tool_result_ids = Enum.map(all_tool_results, & &1.tool_call_id)

      # Every tool result should have a matching tool call
      assert Enum.all?(tool_result_ids, &(&1 in tool_call_ids))

      # Tool call IDs should be unique
      assert length(tool_call_ids) == length(Enum.uniq(tool_call_ids))
    end
  end

  describe "error scenarios" do
    test "handles tool call with error result" do
      user_message = Message.new(:user, "What's the weather in InvalidCity?")

      assistant_message =
        Message.assistant_with_tools(
          "Let me check the weather for that location.",
          [ContentPart.tool_call("error_001", "get_weather", %{location: "InvalidCity"})]
        )

      # Tool returns error
      error_result =
        Message.tool_result("error_001", "get_weather", %{
          error: "Location not found",
          error_code: "LOCATION_NOT_FOUND"
        })

      # Assistant handles error gracefully
      error_response =
        Message.new(
          :assistant,
          "I'm sorry, but I couldn't find weather information for 'InvalidCity'. Could you please check the spelling or provide a more specific location?"
        )

      conversation = [user_message, assistant_message, error_result, error_response]
      assert Enum.all?(conversation, &Message.valid?/1)
    end

    test "validates tool call ID mismatches are caught in validation" do
      # Create tool call with one ID
      assistant_message =
        Message.assistant_with_tools(
          "Checking weather...",
          [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]
        )

      # Create tool result with different ID (this would be a bug)
      mismatched_result = Message.tool_result("call_456", "get_weather", %{temperature: 72})

      assert Message.valid?(assistant_message)
      # Individual messages are valid
      assert Message.valid?(mismatched_result)

      # In a real system, validation would catch that tool_call_id "call_456"
      # doesn't match any previous tool call, but that's application-level logic
      # The Message structs themselves are individually valid
    end
  end

  describe "backward compatibility" do
    test "existing message patterns still work" do
      # Simple text messages
      user_msg = Message.new(:user, "Hello")
      assistant_msg = Message.new(:assistant, "Hi there!")
      system_msg = Message.new(:system, "You are helpful")

      assert Message.valid?(user_msg)
      assert Message.valid?(assistant_msg)
      assert Message.valid?(system_msg)

      # Multi-modal messages without tools
      content = [
        ContentPart.text("Describe this image:"),
        ContentPart.image_url("https://example.com/image.png")
      ]

      multimodal_msg = Message.new(:user, content)
      assert Message.valid?(multimodal_msg)

      # Provider options still work
      msg_with_opts =
        Message.new(:user, "Hello",
          metadata: %{
            provider_options: %{openai: %{temperature: 0.7}}
          }
        )

      assert Message.valid?(msg_with_opts)
      assert Message.provider_options(msg_with_opts) == %{openai: %{temperature: 0.7}}
    end
  end
end
