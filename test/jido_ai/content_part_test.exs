defmodule Jido.AI.ContentPartTest do
  use ExUnit.Case

  alias Jido.AI.ContentPart

  doctest ContentPart

  describe "text/1" do
    test "creates a text content part" do
      part = ContentPart.text("Hello world")

      assert %ContentPart{
               type: :text,
               text: "Hello world",
               metadata: nil
             } = part
    end

    test "handles empty text" do
      part = ContentPart.text("")

      assert %ContentPart{
               type: :text,
               text: "",
               metadata: nil
             } = part
    end

    test "creates text content part with metadata" do
      metadata = %{provider_options: %{openai: %{image_detail: "high"}}}
      part = ContentPart.text("Hello world", metadata: metadata)

      assert %ContentPart{
               type: :text,
               text: "Hello world",
               metadata: ^metadata
             } = part
    end
  end

  describe "provider_options/1" do
    test "extracts provider options from metadata" do
      provider_opts = %{openai: %{image_detail: "high"}}
      metadata = %{provider_options: provider_opts}
      part = ContentPart.text("Hello", metadata: metadata)

      assert ContentPart.provider_options(part) == provider_opts
    end

    test "returns empty map when no metadata" do
      part = ContentPart.text("Hello")
      assert ContentPart.provider_options(part) == %{}
    end

    test "returns empty map when no provider_options in metadata" do
      part = ContentPart.text("Hello", metadata: %{other: "value"})
      assert ContentPart.provider_options(part) == %{}
    end
  end

  describe "image_url/1" do
    test "creates an image URL content part" do
      url = "https://example.com/image.png"
      part = ContentPart.image_url(url)

      assert %ContentPart{
               type: :image_url,
               url: ^url,
               metadata: nil
             } = part
    end

    test "creates image URL content part with metadata" do
      url = "https://example.com/image.png"
      metadata = %{provider_options: %{openai: %{detail: "high"}}}
      part = ContentPart.image_url(url, metadata: metadata)

      assert %ContentPart{
               type: :image_url,
               url: ^url,
               metadata: ^metadata
             } = part
    end
  end

  describe "image_data/2" do
    test "creates an image data content part" do
      # PNG header bytes
      data = <<137, 80, 78, 71>>
      media_type = "image/png"
      part = ContentPart.image_data(data, media_type)

      assert %ContentPart{
               type: :image,
               data: ^data,
               media_type: ^media_type,
               metadata: nil
             } = part
    end

    test "creates image data content part with metadata" do
      data = <<137, 80, 78, 71>>
      media_type = "image/png"
      metadata = %{provider_options: %{openai: %{detail: "low"}}}
      part = ContentPart.image_data(data, media_type, metadata: metadata)

      assert %ContentPart{
               type: :image,
               data: ^data,
               media_type: ^media_type,
               metadata: ^metadata
             } = part
    end
  end

  describe "file/3" do
    test "creates a file content part" do
      # PDF header bytes
      data = <<37, 80, 68, 70>>
      media_type = "application/pdf"
      filename = "document.pdf"
      part = ContentPart.file(data, media_type, filename)

      assert %ContentPart{
               type: :file,
               data: ^data,
               media_type: ^media_type,
               filename: ^filename,
               metadata: nil
             } = part
    end

    test "creates file content part with metadata" do
      data = <<37, 80, 68, 70>>
      media_type = "application/pdf"
      filename = "document.pdf"
      metadata = %{provider_options: %{openai: %{max_tokens: 1000}}}
      part = ContentPart.file(data, media_type, filename, metadata: metadata)

      assert %ContentPart{
               type: :file,
               data: ^data,
               media_type: ^media_type,
               filename: ^filename,
               metadata: ^metadata
             } = part
    end
  end

  describe "valid?/1" do
    test "validates text content parts" do
      part = ContentPart.text("Hello")
      assert ContentPart.valid?(part)
    end

    test "validates image URL content parts" do
      part = ContentPart.image_url("https://example.com/image.png")
      assert ContentPart.valid?(part)
    end

    test "validates image data content parts" do
      part = ContentPart.image_data(<<137, 80, 78, 71>>, "image/png")
      assert ContentPart.valid?(part)
    end

    test "validates file content parts" do
      part = ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "doc.pdf")
      assert ContentPart.valid?(part)
    end

    test "rejects text content parts with empty text" do
      part = %ContentPart{type: :text, text: ""}
      refute ContentPart.valid?(part)
    end

    test "rejects text content parts with nil text" do
      part = %ContentPart{type: :text, text: nil}
      refute ContentPart.valid?(part)
    end

    test "rejects image URL parts with invalid URLs" do
      part = %ContentPart{type: :image_url, url: "not-a-url"}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :image_url, url: ""}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :image_url, url: nil}
      refute ContentPart.valid?(part)
    end

    test "rejects image data parts with invalid media types" do
      part = %ContentPart{type: :image, data: <<1, 2, 3>>, media_type: "text/plain"}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :image, data: <<1, 2, 3>>, media_type: ""}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :image, data: <<1, 2, 3>>, media_type: nil}
      refute ContentPart.valid?(part)
    end

    test "rejects image data parts with empty data" do
      part = %ContentPart{type: :image, data: <<>>, media_type: "image/png"}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :image, data: nil, media_type: "image/png"}
      refute ContentPart.valid?(part)
    end

    test "rejects file parts with invalid media types" do
      part = %ContentPart{type: :file, data: <<1, 2, 3>>, media_type: "invalid", filename: "doc.txt"}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :file, data: <<1, 2, 3>>, media_type: "", filename: "doc.txt"}
      refute ContentPart.valid?(part)
    end

    test "rejects file parts with empty filename" do
      part = %ContentPart{type: :file, data: <<1, 2, 3>>, media_type: "text/plain", filename: ""}
      refute ContentPart.valid?(part)

      part = %ContentPart{type: :file, data: <<1, 2, 3>>, media_type: "text/plain", filename: nil}
      refute ContentPart.valid?(part)
    end

    test "rejects non-ContentPart structs" do
      refute ContentPart.valid?(%{type: :text, text: "Hello"})
      refute ContentPart.valid?("not a content part")
      refute ContentPart.valid?(nil)
    end
  end

  describe "to_map/1" do
    test "converts text content part to map" do
      part = ContentPart.text("Hello world")
      map = ContentPart.to_map(part)

      assert %{type: "text", text: "Hello world"} = map
    end

    test "converts image URL content part to map" do
      part = ContentPart.image_url("https://example.com/image.png")
      map = ContentPart.to_map(part)

      assert %{type: "image_url", image_url: %{url: "https://example.com/image.png"}} = map
    end

    test "converts image data content part to map with base64 encoding" do
      # PNG header
      data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      part = ContentPart.image_data(data, "image/png")
      map = ContentPart.to_map(part)

      expected_base64 = Elixir.Base.encode64(data)
      expected_url = "data:image/png;base64,#{expected_base64}"

      assert %{type: "image_url", image_url: %{url: ^expected_url}} = map
    end

    test "converts file content part to map with base64 encoding" do
      # PDF header
      data = <<37, 80, 68, 70, 45, 49, 46, 52>>
      part = ContentPart.file(data, "application/pdf", "document.pdf")
      map = ContentPart.to_map(part)

      expected_base64 = Elixir.Base.encode64(data)

      assert %{
               type: "file",
               file: %{
                 data: ^expected_base64,
                 media_type: "application/pdf",
                 filename: "document.pdf"
               }
             } = map
    end
  end
end
