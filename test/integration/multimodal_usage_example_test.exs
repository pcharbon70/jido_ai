defmodule Jido.AI.MultimodalUsageExampleTest do
  @moduledoc """
  Test demonstrating the exact usage example from the Iteration 4 requirements.
  """

  use ExUnit.Case

  alias Jido.AI.{ContentPart, Message}

  @tag :example
  test "multi-modal content works as specified in requirements" do
    # Sample data for testing
    # PDF header + newline
    pdf_data = <<37, 80, 68, 70, 45, 49, 46, 52, 10>>

    # Mixed content message as specified in requirements
    message = %Message{
      role: :user,
      content: [
        ContentPart.text("Describe this image:"),
        ContentPart.image_url("https://example.com/image.png"),
        ContentPart.file(pdf_data, "application/pdf", "document.pdf")
      ]
    }

    # Validate the message structure
    assert %Message{
             role: :user,
             content: [
               %ContentPart{type: :text, text: "Describe this image:"},
               %ContentPart{type: :image_url, url: "https://example.com/image.png"},
               %ContentPart{
                 type: :file,
                 data: ^pdf_data,
                 media_type: "application/pdf",
                 filename: "document.pdf"
               }
             ]
           } = message

    # Validate the message is valid
    assert Message.valid?(message)

    # Validate individual content parts
    [text_part, image_part, file_part] = message.content

    assert ContentPart.valid?(text_part)
    assert ContentPart.valid?(image_part)
    assert ContentPart.valid?(file_part)

    # Test that content parts convert to proper OpenAI format
    text_map = ContentPart.to_map(text_part)
    assert %{type: "text", text: "Describe this image:"} = text_map

    image_map = ContentPart.to_map(image_part)

    assert %{
             type: "image_url",
             image_url: %{url: "https://example.com/image.png"}
           } = image_map

    file_map = ContentPart.to_map(file_part)
    expected_base64 = Base.encode64(pdf_data)

    assert %{
             type: "file",
             file: %{
               data: ^expected_base64,
               media_type: "application/pdf",
               filename: "document.pdf"
             }
           } = file_map

    # This structure could now be passed to Jido.AI.generate_text
    # For example: Jido.AI.generate_text("openai:gpt-4o", [message])
    # (We can't test the actual API call here due to test isolation)
  end

  @tag :helper_functions
  test "helper functions create the same content as manual construction" do
    # Helper function approach
    message1 = Message.user_with_image("Describe this image:", "https://example.com/image.png")

    # Manual construction approach
    message2 = %Message{
      role: :user,
      content: [
        ContentPart.text("Describe this image:"),
        ContentPart.image_url("https://example.com/image.png")
      ]
    }

    # Both should be equivalent
    assert message1.role == message2.role
    assert message1.content == message2.content
    assert Message.valid?(message1)
    assert Message.valid?(message2)
  end

  @tag :content_validation
  test "content validation prevents invalid data" do
    # Invalid URL
    invalid_url_part = %ContentPart{type: :image_url, url: "not-a-url"}
    refute ContentPart.valid?(invalid_url_part)

    # Invalid media type for image
    invalid_image_part = %ContentPart{type: :image, data: <<1, 2, 3>>, media_type: "text/plain"}
    refute ContentPart.valid?(invalid_image_part)

    # Empty filename
    invalid_file_part = %ContentPart{
      type: :file,
      data: <<1, 2, 3>>,
      media_type: "application/pdf",
      filename: ""
    }

    refute ContentPart.valid?(invalid_file_part)

    # Message with invalid content parts should be invalid
    message_with_invalid = %Message{
      role: :user,
      content: [ContentPart.text("Valid"), invalid_url_part]
    }

    refute Message.valid?(message_with_invalid)
  end
end
