#!/usr/bin/env elixir

# Simple test for generate_object functionality
# Usage: OPENROUTER_API_KEY=your_key elixir scripts/simple_object_test.exs

# Add jido_ai to path
Code.prepend_path("_build/dev/lib/jido_ai/ebin")
Code.prepend_path("../jido/jido/_build/dev/lib/jido/ebin")
Code.prepend_path("../jido_action/_build/dev/lib/jido_action/ebin")
Code.prepend_path("../jido_signal/_build/dev/lib/jido_signal/ebin")

# Start required applications
Application.ensure_all_started(:logger)
Application.ensure_all_started(:jido_ai)

# Simple test
IO.puts("Testing generate_object with Claude 3.5...")

# Define a simple schema
user_schema = [
  name: [type: :string, required: true],
  age: [type: :integer, required: true],
  city: [type: :string, required: true]
]

# Model specification for OpenRouter + Claude 3.5
model = "openrouter:anthropic/claude-3.5-sonnet"
prompt = "Generate a realistic person living in San Francisco"

IO.puts("📡 Calling OpenRouter API...")

case Jido.AI.generate_object(model, prompt, user_schema) do
  {:ok, person} ->
    IO.puts("✅ Success! Generated person:")
    IO.inspect(person, pretty: true)
    
    IO.puts("\n🧪 Validation check:")
    IO.puts("- Name: #{inspect(person.name)} (#{if is_binary(person.name), do: "✅", else: "❌"})")
    IO.puts("- Age: #{inspect(person.age)} (#{if is_integer(person.age), do: "✅", else: "❌"})")
    IO.puts("- City: #{inspect(person.city)} (#{if is_binary(person.city), do: "✅", else: "❌"})")

  {:error, error} ->
    IO.puts("❌ Error:")
    IO.inspect(error, pretty: true)
end

IO.puts("\n🎉 Test completed!")
