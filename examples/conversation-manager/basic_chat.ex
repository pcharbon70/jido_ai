defmodule Examples.ConversationManager.BasicChat do
  @moduledoc """
  Basic multi-turn conversation example with tool integration.

  Demonstrates:
  - Starting a conversation with tools
  - Multiple conversation turns
  - Tool execution (weather lookups)
  - Conversation history tracking
  - Proper conversation cleanup

  ## Usage

      # Run the example
      Examples.ConversationManager.BasicChat.run()

      # Start your own conversation
      {:ok, conv_id} = Examples.ConversationManager.BasicChat.start_chat([WeatherAction])
      {:ok, response} = Examples.ConversationManager.BasicChat.chat(conv_id, "What's the weather?")
      :ok = Examples.ConversationManager.BasicChat.end_chat(conv_id)
  """

  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  @doc """
  Run the basic chat example demonstrating multi-turn conversation.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Conversation Manager: Basic Multi-Turn Chat")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("📝 **Example:** Weather Assistant with Conversation History")
    IO.puts("Demonstrates stateful multi-turn conversations with tool calls\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    # Start conversation with weather tool
    IO.puts("🔧 **Starting conversation with WeatherAction...**")

    case start_chat([MockWeatherAction]) do
      {:ok, conv_id} ->
        IO.puts("✓ Conversation started: #{String.slice(conv_id, 0, 8)}...\n")

        # Conversation flow
        conversation_flow(conv_id)

        # Show final history
        display_conversation_history(conv_id)

        # Cleanup
        end_chat(conv_id)
        IO.puts("\n✓ Conversation ended successfully")

      {:error, reason} ->
        IO.puts("❌ **Error:** Failed to start conversation: #{inspect(reason)}")
    end

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Starts a new conversation with the given tools.
  """
  def start_chat(tools, options \\ %{}) do
    default_options = %{
      model: "gpt-4",
      temperature: 0.7,
      max_tokens: 1000,
      max_tool_calls: 5
    }

    merged_options = Map.merge(default_options, options)

    ToolIntegrationManager.start_conversation(tools, merged_options)
  end

  @doc """
  Sends a message in the conversation and gets a response.
  """
  def chat(conversation_id, message) do
    ToolIntegrationManager.continue_conversation(conversation_id, message)
  end

  @doc """
  Ends the conversation and cleans up resources.
  """
  def end_chat(conversation_id) do
    ToolIntegrationManager.end_conversation(conversation_id)
  end

  @doc """
  Gets the conversation history.
  """
  def get_history(conversation_id) do
    ToolIntegrationManager.get_conversation_history(conversation_id)
  end

  # Private Functions

  defp conversation_flow(conv_id) do
    # Turn 1: Ask about weather in Paris
    IO.puts("💬 **User:** What's the weather like in Paris?")

    case chat(conv_id, "What's the weather like in Paris?") do
      {:ok, response} ->
        display_response(response, 1)

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
    end

    # Short delay for readability
    Process.sleep(500)

    # Turn 2: Ask about weather in London
    IO.puts("💬 **User:** And what about London?")

    case chat(conv_id, "And what about London?") do
      {:ok, response} ->
        display_response(response, 2)

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
    end

    # Short delay for readability
    Process.sleep(500)

    # Turn 3: Ask comparative question (uses context)
    IO.puts("💬 **User:** Which city is warmer?")

    case chat(conv_id, "Which city is warmer?") do
      {:ok, response} ->
        display_response(response, 3)

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
    end
  end

  defp display_response(response, turn_number) do
    IO.puts("\n🤖 **Assistant (Turn #{turn_number}):**")

    # Display content
    content = Map.get(response, :content, "")

    if content != "" do
      IO.puts("   #{content}")
    end

    # Display tool calls if any
    tool_calls = Map.get(response, :tool_calls, [])

    if length(tool_calls) > 0 do
      IO.puts("\n   🔧 Tool Calls Made:")

      Enum.each(tool_calls, fn tool_call ->
        function = Map.get(tool_call, :function, %{})
        name = Map.get(function, :name, "unknown")
        args = Map.get(function, :arguments, %{})

        IO.puts("      • #{name}(#{format_args(args)})")
      end)
    end

    # Display usage stats if available
    usage = Map.get(response, :usage, %{})

    if map_size(usage) > 0 do
      total = Map.get(usage, :total_tokens, 0)
      IO.puts("\n   📊 Tokens Used: #{total}")
    end

    IO.puts("")
  end

  defp format_args(args) when is_map(args) do
    args
    |> Enum.map(fn {k, v} -> "#{k}: \"#{v}\"" end)
    |> Enum.join(", ")
  end

  defp format_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> format_args(decoded)
      {:error, _} -> args
    end
  end

  defp format_args(args), do: inspect(args)

  defp display_conversation_history(conv_id) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("\n📜 **Conversation History:**\n")

    case get_history(conv_id) do
      {:ok, history} ->
        IO.puts("   Total messages: #{length(history)}\n")

        history
        |> Enum.with_index(1)
        |> Enum.each(fn {msg, idx} ->
          role = Map.get(msg, :role, "unknown")
          content = Map.get(msg, :content, "")
          timestamp = Map.get(msg, :timestamp)

          # Format role
          role_display =
            case role do
              "user" -> "👤 User"
              "assistant" -> "🤖 Assistant"
              "tool" -> "🔧 Tool"
              _ -> role
            end

          IO.puts("   #{idx}. #{role_display}")

          # Show content preview
          preview =
            if String.length(content) > 60 do
              String.slice(content, 0, 60) <> "..."
            else
              content
            end

          IO.puts("      \"#{preview}\"")

          # Show timestamp if available
          if timestamp do
            time_str = Calendar.strftime(timestamp, "%H:%M:%S")
            IO.puts("      ⏰ #{time_str}")
          end

          IO.puts("")
        end)

      {:error, reason} ->
        IO.puts("   ❌ Error retrieving history: #{inspect(reason)}")
    end
  end
end

# Mock Weather Action for demonstration purposes
defmodule Examples.ConversationManager.MockWeatherAction do
  @moduledoc """
  Mock weather action for demonstration.
  Returns simulated weather data based on location.
  """

  use Jido.Action,
    name: "get_weather",
    description: "Get current weather information for a city",
    schema: [
      location: [
        type: :string,
        required: true,
        doc: "City name to get weather for"
      ],
      units: [
        type: {:in, ["celsius", "fahrenheit"]},
        default: "celsius",
        doc: "Temperature units"
      ]
    ]

  @impl true
  def run(params, _context) do
    location = params.location
    units = Map.get(params, :units, "celsius")

    # Simulate weather data
    weather_data = get_mock_weather(location, units)

    {:ok, weather_data}
  end

  defp get_mock_weather(location, units) do
    # Simulated weather based on city
    {temp, description} =
      case String.downcase(location) do
        loc when loc in ["paris", "france"] ->
          if units == "celsius", do: {18, "Partly cloudy"}, else: {64, "Partly cloudy"}

        loc when loc in ["london", "england", "uk"] ->
          if units == "celsius", do: {15, "Rainy"}, else: {59, "Rainy"}

        loc when loc in ["tokyo", "japan"] ->
          if units == "celsius", do: {22, "Clear"}, else: {72, "Clear"}

        loc when loc in ["new york", "nyc"] ->
          if units == "celsius", do: {20, "Sunny"}, else: {68, "Sunny"}

        _ ->
          if units == "celsius", do: {20, "Partly cloudy"}, else: {68, "Partly cloudy"}
      end

    unit_symbol = if units == "celsius", do: "°C", else: "°F"

    %{
      location: location,
      temperature: temp,
      units: units,
      description: description,
      formatted: "#{temp}#{unit_symbol}, #{description}"
    }
  end
end
