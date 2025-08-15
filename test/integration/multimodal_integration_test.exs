defmodule Jido.AI.MultimodalIntegrationTest do
  @moduledoc """
  Integration test showing multi-modal content support works end-to-end.

  This test validates that the Iteration 4 implementation of multi-modal
  content support is working as designed.
  """

  use ExUnit.Case

  alias Jido.AI.{ContentPart, Message}

  describe "multi-modal content integration" do
    test "ContentPart.image_url/2 creates valid image URL content parts" do
      part = ContentPart.image_url("https://example.com/image.png")

      assert %ContentPart{
               type: :image_url,
               url: "https://example.com/image.png"
             } = part

      assert ContentPart.valid?(part)

      # Test conversion to OpenAI format
      map = ContentPart.to_map(part)

      assert %{
               type: "image_url",
               image_url: %{url: "https://example.com/image.png"}
             } = map
    end

    test "ContentPart.image_data/3 creates valid image data content parts" do
      # PNG header
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      part = ContentPart.image_data(image_data, "image/png")

      assert %ContentPart{
               type: :image,
               data: ^image_data,
               media_type: "image/png"
             } = part

      assert ContentPart.valid?(part)

      # Test conversion to data URL format
      map = ContentPart.to_map(part)
      expected_base64 = Base.encode64(image_data)
      expected_url = "data:image/png;base64,#{expected_base64}"

      assert %{
               type: "image_url",
               image_url: %{url: ^expected_url}
             } = map
    end

    test "ContentPart.file/4 creates valid file content parts" do
      # PDF header
      file_data = <<37, 80, 68, 70, 45, 49, 46, 52>>
      part = ContentPart.file(file_data, "application/pdf", "document.pdf")

      assert %ContentPart{
               type: :file,
               data: ^file_data,
               media_type: "application/pdf",
               filename: "document.pdf"
             } = part

      assert ContentPart.valid?(part)

      # Test conversion to structured format
      map = ContentPart.to_map(part)
      expected_base64 = Base.encode64(file_data)

      assert %{
               type: "file",
               file: %{
                 data: ^expected_base64,
                 media_type: "application/pdf",
                 filename: "document.pdf"
               }
             } = map
    end

    test "Message.user_with_image/3 creates valid multi-modal messages" do
      message = Message.user_with_image("Describe this image:", "https://example.com/image.png")

      assert %Message{
               role: :user,
               content: [
                 %ContentPart{type: :text, text: "Describe this image:"},
                 %ContentPart{type: :image_url, url: "https://example.com/image.png"}
               ]
             } = message

      assert Message.valid?(message)
    end

    test "Message.user_multimodal/2 creates valid complex multi-modal messages" do
      content_parts = [
        ContentPart.text("Analyze this image and document:"),
        ContentPart.image_url("https://example.com/image.png"),
        ContentPart.image_data(<<137, 80, 78, 71>>, "image/png"),
        ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "report.pdf")
      ]

      message = Message.user_multimodal(content_parts)

      assert %Message{
               role: :user,
               content: ^content_parts
             } = message

      assert Message.valid?(message)

      # Ensure all content parts are valid
      assert Enum.all?(content_parts, &ContentPart.valid?/1)
    end

    test "validation rejects invalid content parts in messages" do
      invalid_content_parts = [
        ContentPart.text("Valid text"),
        # Invalid empty URL
        %ContentPart{type: :image_url, url: ""}
      ]

      message = Message.user_multimodal(invalid_content_parts)

      # Should be invalid because one content part is invalid
      refute Message.valid?(message)
    end

    test "backward compatibility - text-only messages still work" do
      # String content
      message1 = Message.new(:user, "Hello world")
      assert Message.valid?(message1)

      # Single text content part
      message2 = Message.new(:user, [ContentPart.text("Hello world")])
      assert Message.valid?(message2)

      # Both should work the same way
      assert message1.content == "Hello world"
      assert [%ContentPart{type: :text, text: "Hello world"}] = message2.content
    end
  end
end
