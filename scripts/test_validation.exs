#!/usr/bin/env elixir

# Test schema validation by creating a mock response that should fail validation
# Usage: OPENROUTER_API_KEY=your_key elixir scripts/test_validation.exs

# Add jido_ai to path
Code.prepend_path("_build/dev/lib/jido_ai/ebin")
Code.prepend_path("../jido/jido/_build/dev/lib/jido_action/ebin")
Code.prepend_path("../jido_signal/_build/dev/lib/jido_signal/ebin")

# Start required applications
Application.ensure_all_started(:logger)
Application.ensure_all_started(:jido_ai)

# Test manual validation
IO.puts("Testing ObjectSchema validation...")

user_schema = [
  name: [type: :string, required: true],
  age: [type: :integer, required: true],
  city: [type: :string, required: true]
]

# Test valid data
valid_data = %{"name" => "John", "age" => 30, "city" => "SF"}
{:ok, schema_struct} = Jido.AI.ObjectSchema.new(properties: user_schema)

case Jido.AI.ObjectSchema.validate(schema_struct, valid_data) do
  {:ok, validated} ->
    IO.puts("✅ Valid data passed: #{inspect(validated)}")
  {:error, error} ->
    IO.puts("❌ Valid data failed: #{inspect(error)}")
end

# Test invalid data (missing required field)
invalid_data = %{"name" => "John", "city" => "SF"}  # missing age

case Jido.AI.ObjectSchema.validate(schema_struct, invalid_data) do
  {:ok, validated} ->
    IO.puts("❌ Invalid data unexpectedly passed: #{inspect(validated)}")
  {:error, error} ->
    IO.puts("✅ Invalid data correctly failed validation:")
    IO.puts("   #{Exception.message(error)}")
end

# Test invalid data (wrong type)
wrong_type_data = %{"name" => "John", "age" => "thirty", "city" => "SF"}

case Jido.AI.ObjectSchema.validate(schema_struct, wrong_type_data) do
  {:ok, validated} ->
    IO.puts("❌ Wrong type data unexpectedly passed: #{inspect(validated)}")
  {:error, error} ->
    IO.puts("✅ Wrong type data correctly failed validation:")
    IO.puts("   #{Exception.message(error)}")
end

IO.puts("\n🎉 Validation tests completed!")
