#!/usr/bin/env elixir

# Demo script showcasing the clean jido_ai API with seamless action integration
#
# This script demonstrates the new, simplified API where actions can be passed
# directly to generate_text/3 and stream_text/3 via options, keeping the 
# top-level API surface minimal and clean.
#
# Run with: elixir demo_clean_api.exs

Mix.install([
  {:jido_ai, path: "."},
  {:jido_action, path: "../jido_action"},
  {:jido, path: "../jido"}
])

require Logger

defmodule DemoCleanAPI do
  @moduledoc """
  Demonstrates the clean jido_ai API with seamless action integration.
  """

  import Jido.AI.Messages

  def main do
    Logger.info("🚀 Jido AI Clean API Demo")
    Logger.info("Testing seamless action integration...")

    # Available actions for AI to use
    actions = [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Weather
    ]

    # Demo 1: Basic generation with actions (new clean API)
    Logger.info("\n📝 Demo 1: Clean API - generate_text with actions")
    
    result = Jido.AI.generate_text(
      "openai:gpt-4o-mini",
      "What is 15 + 7? Also, what's the weather like in San Francisco?",
      actions: actions,
      system_prompt: "You are a helpful assistant with access to math and weather tools."
    )

    case result do
      {:ok, response} ->
        Logger.info("✅ Success: #{response}")
      {:error, reason} ->
        Logger.error("❌ Error: #{inspect(reason)}")
    end

    # Demo 2: Streaming with actions  
    Logger.info("\n🌊 Demo 2: Clean API - stream_text with actions")
    
    stream_result = Jido.AI.stream_text(
      "openai:gpt-4o-mini", 
      "Calculate 25 - 8 for me",
      actions: [Jido.Tools.Arithmetic.Subtract],
      system_prompt: "You are a math assistant."
    )

    case stream_result do
      {:ok, stream} ->
        Logger.info("✅ Streaming started...")
        stream
        |> Stream.each(&IO.write/1)
        |> Stream.run()
        IO.puts("")
      {:error, reason} ->
        Logger.error("❌ Stream error: #{inspect(reason)}")
    end

    # Demo 3: Raw tool definitions (alternative to actions)
    Logger.info("\n🔧 Demo 3: Clean API - generate_text with raw tools")
    
    custom_tools = [
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_time", 
          "description" => "Get current time",
          "parameters" => %{
            "type" => "object",
            "properties" => %{},
            "required" => []
          }
        }
      }
    ]

    tool_result = Jido.AI.generate_text(
      "openai:gpt-4o-mini",
      "What tools do you have available?",
      tools: custom_tools
    )

    case tool_result do
      {:ok, response} ->
        Logger.info("✅ Tool integration: #{response}")
      {:error, reason} ->
        Logger.error("❌ Tool error: #{inspect(reason)}")
    end

    # Demo 4: Backward compatibility test (deprecated API)
    Logger.info("\n⚠️  Demo 4: Deprecated API still works")
    
    deprecated_result = Jido.AI.generate_with_tools(
      "openai:gpt-4o-mini",
      [user("What is 5 + 5?")],
      [Jido.Tools.Arithmetic.Add]
    )

    case deprecated_result do
      {:ok, response} ->
        Logger.info("✅ Deprecated API works: #{response}")
      {:error, reason} ->
        Logger.error("❌ Deprecated error: #{inspect(reason)}")
    end

    Logger.info("\n🎉 Demo complete! The clean API successfully integrates actions seamlessly.")
  end
end

# Run the demo
DemoCleanAPI.main()
