#!/usr/bin/env elixir

# Test script for generate_object with real LLM provider
# Usage: OPENROUTER_API_KEY=your_key elixir scripts/test_generate_object.exs

# Add jido_ai to path
Code.prepend_path("_build/dev/lib/jido_ai/ebin")
Code.prepend_path("../jido/jido/_build/dev/lib/jido/ebin")
Code.prepend_path("../jido_action/_build/dev/lib/jido_action/ebin")
Code.prepend_path("../jido_signal/_build/dev/lib/jido_signal/ebin")

# Start required applications
Application.ensure_all_started(:logger)
Application.ensure_all_started(:jido_ai)

defmodule GenerateObjectTest do
  @moduledoc """
  Test script to validate generate_object works with real LLM providers.
  
  This script tests the new generate_object functionality using OpenRouter
  with Claude 3.5 Sonnet to generate structured data.
  """

  def run do
    IO.puts("🚀 Testing Jido.AI.generate_object with OpenRouter + Claude 3.5")
    IO.puts("=" |> String.duplicate(60))

    # Check API key
    case System.get_env("OPENROUTER_API_KEY") do
      nil ->
        IO.puts("❌ Error: OPENROUTER_API_KEY environment variable not set")
        IO.puts("Please run: OPENROUTER_API_KEY=your_key elixir scripts/test_generate_object.exs")
        exit(1)

      key when is_binary(key) ->
        IO.puts("✅ API key found")
        test_object_generation()
    end
  end

  defp test_object_generation do
    # Test 1: Basic object generation
    IO.puts("\n📋 Test 1: Basic User Profile Object")
    user_schema = [
      name: [type: :string, required: true],
      age: [type: :integer, required: true],
      email: [type: :string, required: true],
      skills: [type: {:list, :string}, default: []]
    ]

    model = "openrouter:anthropic/claude-3.5-sonnet"
    prompt = "Generate a realistic user profile for a software engineer"

    case Jido.AI.generate_object(model, prompt, user_schema) do
      {:ok, user} ->
        IO.puts("✅ Success! Generated user:")
        IO.inspect(user, pretty: true)

      {:error, error} ->
        IO.puts("❌ Error generating user object:")
        IO.inspect(error, pretty: true)
    end

    # Test 2: Array generation
    IO.puts("\n📋 Test 2: Array of Tasks")
    task_schema = [
      title: [type: :string, required: true],
      priority: [type: :string, required: true],
      completed: [type: :boolean, default: false]
    ]

    array_prompt = "Generate 3 software development tasks"

    case Jido.AI.generate_object(model, array_prompt, task_schema, output_type: :array) do
      {:ok, tasks} ->
        IO.puts("✅ Success! Generated tasks:")
        IO.inspect(tasks, pretty: true)

      {:error, error} ->
        IO.puts("❌ Error generating task array:")
        IO.inspect(error, pretty: true)
    end

    # Test 3: Enum selection
    IO.puts("\n📋 Test 3: Programming Language Selection")
    enum_values = ["elixir", "rust", "go", "python", "javascript"]
    enum_prompt = "Choose the best programming language for building concurrent systems"

    case Jido.AI.generate_object(model, enum_prompt, [], output_type: :enum, enum_values: enum_values) do
      {:ok, choice} ->
        IO.puts("✅ Success! LLM chose: #{choice}")

      {:error, error} ->
        IO.puts("❌ Error with enum selection:")
        IO.inspect(error, pretty: true)
    end

    # Test 4: Complex nested object
    IO.puts("\n📋 Test 4: Complex Nested Project Structure")
    project_schema = [
      name: [type: :string, required: true],
      description: [type: :string, required: true],
      technologies: [type: {:list, :string}, required: true],
      team_size: [type: :integer, required: true],
      timeline: [
        type: :map,
        required: true,
        keys: [
          start_date: [type: :string, required: true],
          end_date: [type: :string, required: true],
          milestones: [type: {:list, :string}, default: []]
        ]
      ]
    ]

    complex_prompt = """
    Generate a realistic software project for a team building a web application 
    for expense tracking. Include proper timeline with milestones.
    """

    case Jido.AI.generate_object(model, complex_prompt, project_schema) do
      {:ok, project} ->
        IO.puts("✅ Success! Generated complex project:")
        IO.inspect(project, pretty: true)

      {:error, error} ->
        IO.puts("❌ Error generating complex object:")
        IO.inspect(error, pretty: true)
    end

    IO.puts("\n🎉 Test completed!")
  end
end

# Run the test
GenerateObjectTest.run()
