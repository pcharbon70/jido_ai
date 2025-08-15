defmodule Jido.AI.MessageTest do
  use ExUnit.Case

  alias Jido.AI.{ContentPart, Message}

  doctest Message

  describe "new/3" do
    test "creates a message with role and content" do
      message = Message.new(:user, "Hello world")

      assert %Message{
               role: :user,
               content: "Hello world",
               name: nil,
               tool_call_id: nil,
               tool_calls: nil,
               metadata: nil
             } = message
    end

    test "creates a message with additional options" do
      message = Message.new(:assistant, "Hi there", name: "assistant", metadata: %{key: "value"})

      assert %Message{
               role: :assistant,
               content: "Hi there",
               name: "assistant",
               metadata: %{key: "value"}
             } = message
    end

    test "creates a message with content parts" do
      content_parts = [ContentPart.text("Hello")]
      message = Message.new(:user, content_parts)

      assert %Message{
               role: :user,
               content: ^content_parts
             } = message
    end
  end

  describe "valid?/1" do
    test "validates messages with string content" do
      message = Message.new(:user, "Hello")
      assert Message.valid?(message)
    end

    test "validates messages with content parts list" do
      content_parts = [ContentPart.text("Hello")]
      message = Message.new(:user, content_parts)
      assert Message.valid?(message)
    end

    test "rejects messages with empty string content" do
      message = %Message{role: :user, content: ""}
      refute Message.valid?(message)
    end

    test "rejects messages with empty content parts list" do
      message = %Message{role: :user, content: []}
      refute Message.valid?(message)
    end

    test "rejects messages with invalid roles" do
      message = %Message{role: :invalid_role, content: "Hello"}
      refute Message.valid?(message)
    end

    test "rejects non-Message structs" do
      refute Message.valid?(%{role: :user, content: "Hello"})
      refute Message.valid?("not a message")
      refute Message.valid?(nil)
    end
  end

  describe "provider_options/1" do
    test "extracts provider options from metadata" do
      provider_opts = %{openai: %{reasoning_effort: "low"}}
      metadata = %{provider_options: provider_opts}
      message = Message.new(:user, "Hello", metadata: metadata)

      assert Message.provider_options(message) == provider_opts
    end

    test "returns empty map when no metadata" do
      message = Message.new(:user, "Hello")
      assert Message.provider_options(message) == %{}
    end

    test "returns empty map when no provider_options in metadata" do
      message = Message.new(:user, "Hello", metadata: %{other: "value"})
      assert Message.provider_options(message) == %{}
    end
  end

  describe "user_multimodal/2" do
    test "creates a user message with multi-modal content" do
      content_parts = [
        ContentPart.text("Describe this image:"),
        ContentPart.image_url("https://example.com/image.png")
      ]

      message = Message.user_multimodal(content_parts)

      assert %Message{
               role: :user,
               content: ^content_parts
             } = message
    end

    test "creates a user message with multi-modal content and metadata" do
      content_parts = [ContentPart.text("Hello")]
      metadata = %{provider_options: %{openai: %{reasoning_effort: "low"}}}

      message = Message.user_multimodal(content_parts, metadata: metadata)

      assert %Message{
               role: :user,
               content: ^content_parts,
               metadata: ^metadata
             } = message
    end
  end

  describe "user_with_image/3" do
    test "creates a user message with text and image URL" do
      text = "Describe this image:"
      image_url = "https://example.com/image.png"

      message = Message.user_with_image(text, image_url)

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: ^text},
                 %ContentPart{type: :image_url, url: ^image_url}
               ]
             } = message
    end

    test "creates a user message with text, image URL, and metadata" do
      text = "Describe this image:"
      image_url = "https://example.com/image.png"
      metadata = %{provider_options: %{openai: %{detail: "high"}}}

      message = Message.user_with_image(text, image_url, metadata: metadata)

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: ^text},
                 %ContentPart{type: :image_url, url: ^image_url}
               ],
               metadata: ^metadata
             } = message
    end
  end

  describe "valid?/1 with multi-modal content" do
    test "validates messages with mixed content types" do
      content_parts = [
        ContentPart.text("Analyze this:"),
        ContentPart.image_url("https://example.com/image.png"),
        ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "doc.pdf")
      ]

      message = Message.new(:user, content_parts)
      assert Message.valid?(message)
    end

    test "rejects messages with invalid content parts" do
      content_parts = [
        ContentPart.text("Valid text"),
        # Invalid empty URL
        %ContentPart{type: :image_url, url: ""}
      ]

      message = Message.new(:user, content_parts)
      refute Message.valid?(message)
    end

    test "rejects messages with invalid content part structure" do
      content_parts = [
        ContentPart.text("Valid text"),
        %{type: :text, text: "Not a ContentPart struct"}
      ]

      message = Message.new(:user, content_parts)
      refute Message.valid?(message)
    end
  end

  describe "role validation" do
    test "accepts valid roles with appropriate fields" do
      # Test user, assistant, and system roles
      for role <- [:user, :assistant, :system] do
        message = Message.new(role, "Hello")
        assert Message.valid?(message), "Role #{role} should be valid"
      end

      # Test tool role (requires tool_call_id)
      tool_message = Message.new(:tool, "Result", tool_call_id: "call_123")
      assert Message.valid?(tool_message), "Tool role with tool_call_id should be valid"

      # Tool role without tool_call_id should be invalid
      invalid_tool_message = Message.new(:tool, "Result")
      refute Message.valid?(invalid_tool_message), "Tool role without tool_call_id should be invalid"
    end
  end
end
