defmodule Jido.AI.RichPromptsIntegrationTest do
  @moduledoc """
  Integration tests demonstrating the complete rich prompts system.

  These tests validate that the Messages API creates valid structures that work
  with the overall system architecture.
  """

  use ExUnit.Case, async: true

  import Jido.AI.Messages

  alias Jido.AI.Messages
  alias Jido.AI.{ContentPart, Message}

  @moduletag :integration

  describe "message structure validation" do
    test "creates valid message arrays with all helper functions" do
      messages = [
        system("You are a helpful coding assistant"),
        user("Explain pattern matching in Elixir"),
        assistant("Pattern matching is a powerful feature..."),
        user("Can you show an example?")
      ]

      # Validate structure
      assert :ok = Messages.validate_messages(messages)
      assert length(messages) == 4
      assert Enum.all?(messages, &match?(%Message{}, &1))

      # Check roles
      roles = Enum.map(messages, & &1.role)
      assert [:system, :user, :assistant, :user] == roles
    end

    test "creates valid multi-modal content structures" do
      messages = [
        user_with_image("Describe this code screenshot", "https://example.com/code.png"),
        assistant("This code shows a GenServer implementation with handle_call/3"),
        user("What improvements would you suggest?")
      ]

      assert :ok = Messages.validate_messages(messages)

      # Check first message has multi-modal content
      [first_message | _] = messages
      assert match?(%Message{role: :user, content: [_, _]}, first_message)

      [text_part, image_part] = first_message.content
      assert %ContentPart{type: :text, text: "Describe this code screenshot"} = text_part
      assert %ContentPart{type: :image_url, url: "https://example.com/code.png"} = image_part
    end

    test "creates valid tool result structures in conversation flow" do
      messages = [
        user("What's the weather like in San Francisco?"),
        assistant("I'll check the weather for you"),
        tool_result("call_123", "get_weather", %{
          temperature: 68,
          condition: "sunny",
          humidity: 65
        }),
        assistant("Based on the weather data, it's 68°F and sunny in San Francisco!")
      ]

      assert :ok = Messages.validate_messages(messages)

      # Check tool result message structure
      tool_message = Enum.at(messages, 2)
      assert match?(%Message{role: :tool, tool_call_id: "call_123"}, tool_message)
      assert [%ContentPart{type: :tool_result}] = tool_message.content
    end

    test "validates system prompt with message tuple structures" do
      system_prompt = "You are an expert Elixir developer who writes clean, idiomatic code"

      messages = [
        user("How do I handle errors in GenServers?"),
        assistant("There are several patterns for error handling in GenServers..."),
        user("Show me a practical example")
      ]

      # Validate individual components
      assert is_binary(system_prompt)
      assert :ok = Messages.validate_messages(messages)

      # Validate tuple structure
      prompt_tuple = {system_prompt, messages}
      assert {prompt, msgs} = prompt_tuple
      assert is_binary(prompt)
      assert is_list(msgs)
    end
  end

  describe "mixed content types in conversation" do
    test "combines text, images, and files in single conversation" do
      pdf_data = <<"%PDF-1.4\n%âãÏÓ\n1 0 obj\n...">>

      messages = [
        system("You are a data analyst who can analyze both visual and document data"),
        user_with_image("Here's a sales chart", "https://example.com/chart.png"),
        assistant("I can see the sales data shows an upward trend in Q3."),
        user_with_file("Now analyze this detailed report", pdf_data, "application/pdf", "q3_report.pdf"),
        assistant("Based on both the chart and report, I can provide deeper insights."),
        user("What are your key recommendations?")
      ]

      # Validate overall structure
      assert :ok = Messages.validate_messages(messages)
      assert length(messages) == 6

      # Check multi-modal content types
      [_, image_msg, _, file_msg, _, _] = messages

      # Verify image message structure
      assert match?(%Message{role: :user, content: [_, _]}, image_msg)
      [_, image_part] = image_msg.content
      assert %ContentPart{type: :image_url} = image_part

      # Verify file message structure
      assert match?(%Message{role: :user, content: [_, _]}, file_msg)
      [_, file_part] = file_msg.content
      assert %ContentPart{type: :file, media_type: "application/pdf"} = file_part
    end
  end

  describe "message validation helpers" do
    test "validate_messages/1 works with conversation flows" do
      messages = [
        system("You are helpful"),
        user("Hello"),
        assistant("Hi there!"),
        tool_result("call_1", "search", ["result1", "result2"]),
        user_with_image("Look at this", "https://example.com/image.png")
      ]

      assert :ok = Messages.validate_messages(messages)
    end

    test "validate_messages/1 catches invalid messages in flows" do
      messages = [
        user("Hello"),
        # Not a Message struct
        %{invalid: "message"},
        assistant("Hi")
      ]

      assert {:error, reason} = Messages.validate_messages(messages)
      assert String.contains?(reason, "Message at index 1")
      assert String.contains?(reason, "Not a valid Message struct")
    end
  end

  describe "usage examples and patterns" do
    test "demonstrates common conversation patterns" do
      # Simple Q&A pattern
      simple_messages = [
        system("You are a helpful assistant"),
        user("Hello"),
        assistant("Hi there!"),
        user("How are you?")
      ]

      assert :ok = Messages.validate_messages(simple_messages)

      # Tool usage pattern
      tool_messages = [
        user("What's the weather?"),
        assistant("I'll check the weather for you"),
        tool_result("weather_call", "get_weather", %{temp: 72, condition: "sunny"}),
        assistant("It's 72°F and sunny!")
      ]

      assert :ok = Messages.validate_messages(tool_messages)

      # Multi-modal pattern
      multimodal_messages = [
        user_with_image("Describe this", "https://example.com/image.png"),
        assistant("I see an image with..."),
        user("What about this file?")
      ]

      assert :ok = Messages.validate_messages(multimodal_messages)
    end

    test "validates various prompt formats" do
      # String format (legacy)
      string_prompt = "Hello world"
      assert is_binary(string_prompt)

      # Message array format
      message_array = [user("Hello world")]
      assert :ok = Messages.validate_messages(message_array)

      # System + messages tuple format
      system_tuple = {"You are helpful", [user("Hello")]}
      {system_prompt, messages} = system_tuple
      assert is_binary(system_prompt)
      assert :ok = Messages.validate_messages(messages)
    end
  end
end
