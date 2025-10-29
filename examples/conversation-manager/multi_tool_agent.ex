defmodule Examples.ConversationManager.MultiToolAgent do
  @moduledoc """
  Advanced conversation agent with multiple tools and sophisticated state management.

  Demonstrates:
  - Multiple tool integration (Weather, Calculator, Search)
  - Error handling and recovery
  - Conversation metadata tracking
  - History analysis and statistics
  - Conditional tool execution
  - Tool timeout configuration
  - Conversation state inspection

  ## Usage

      # Run the full example
      Examples.ConversationManager.MultiToolAgent.run()

      # Create a custom agent
      {:ok, agent} = Examples.ConversationManager.MultiToolAgent.create_agent(%{
        tools: [WeatherAction, CalculatorAction],
        model: "gpt-4",
        temperature: 0.7
      })

      # Process messages with the agent
      {:ok, response} = Examples.ConversationManager.MultiToolAgent.process(
        agent,
        "What's 15 * 23?"
      )

      # Analyze agent conversation
      stats = Examples.ConversationManager.MultiToolAgent.get_statistics(agent)

      # Cleanup
      :ok = Examples.ConversationManager.MultiToolAgent.destroy_agent(agent)
  """

  alias Jido.AI.ReqLlmBridge.{ConversationManager, ToolIntegrationManager}
  require Logger

  @default_options %{
    model: "gpt-4",
    temperature: 0.7,
    max_tokens: 1500,
    max_tool_calls: 10,
    timeout: 45_000
  }

  @type agent :: %{
          conversation_id: String.t(),
          tools: [module()],
          options: map(),
          created_at: DateTime.t(),
          message_count: non_neg_integer()
        }

  @doc """
  Runs the advanced multi-tool agent example.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Conversation Manager: Multi-Tool Agent")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("📝 **Example:** Advanced agent with multiple tools and error handling")
    IO.puts("Features: Weather, Calculator, Search with retry logic\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    # Create agent with multiple tools
    tools = [MockWeatherAction, MockCalculatorAction, MockSearchAction]

    options = %{
      model: "gpt-4",
      temperature: 0.7,
      max_tool_calls: 10,
      timeout: 30_000
    }

    IO.puts("🔧 **Creating agent with #{length(tools)} tools...**")

    case create_agent(%{tools: tools, options: options}) do
      {:ok, agent} ->
        display_agent_info(agent)

        # Run conversation scenarios
        run_scenarios(agent)

        # Display final statistics
        display_final_statistics(agent)

        # Cleanup
        destroy_agent(agent)
        IO.puts("\n✓ Agent destroyed successfully")

      {:error, reason} ->
        IO.puts("❌ **Error:** Failed to create agent: #{inspect(reason)}")
    end

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Creates a new multi-tool agent.
  """
  @spec create_agent(map()) :: {:ok, agent()} | {:error, term()}
  def create_agent(config) do
    tools = Map.get(config, :tools, [])
    user_options = Map.get(config, :options, %{})

    options = Map.merge(@default_options, user_options)

    case ToolIntegrationManager.start_conversation(tools, options) do
      {:ok, conversation_id} ->
        agent = %{
          conversation_id: conversation_id,
          tools: tools,
          options: options,
          created_at: DateTime.utc_now(),
          message_count: 0
        }

        {:ok, agent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Processes a message with the agent, including error handling and retry logic.
  """
  @spec process(agent(), String.t(), keyword()) :: {:ok, map(), agent()} | {:error, term()}
  def process(agent, message, opts \\ []) do
    retries = Keyword.get(opts, :retries, 2)
    log_enabled = Keyword.get(opts, :log, true)

    if log_enabled do
      Logger.info("Processing message",
        conversation_id: agent.conversation_id,
        message_length: String.length(message)
      )
    end

    case process_with_retry(agent, message, retries) do
      {:ok, response} ->
        updated_agent = %{agent | message_count: agent.message_count + 1}

        if log_enabled do
          Logger.info("Message processed successfully",
            conversation_id: agent.conversation_id,
            tool_calls: length(Map.get(response, :tool_calls, []))
          )
        end

        {:ok, response, updated_agent}

      {:error, reason} = error ->
        if log_enabled do
          Logger.error("Message processing failed",
            conversation_id: agent.conversation_id,
            error: inspect(reason)
          )
        end

        error
    end
  end

  @doc """
  Gets conversation statistics for the agent.
  """
  @spec get_statistics(agent()) :: {:ok, map()} | {:error, term()}
  def get_statistics(agent) do
    with {:ok, history} <- ToolIntegrationManager.get_conversation_history(agent.conversation_id),
         {:ok, metadata} <-
           ConversationManager.get_conversation_metadata(agent.conversation_id) do
      stats = %{
        conversation_id: agent.conversation_id,
        age_minutes: DateTime.diff(DateTime.utc_now(), agent.created_at, :minute),
        total_messages: metadata.message_count,
        user_messages: count_messages_by_role(history, "user"),
        assistant_messages: count_messages_by_role(history, "assistant"),
        tool_messages: count_messages_by_role(history, "tool"),
        tools_available: length(agent.tools),
        tool_names: Enum.map(agent.tools, &get_tool_name/1)
      }

      {:ok, stats}
    end
  end

  @doc """
  Analyzes conversation history and returns insights.
  """
  @spec analyze_conversation(agent()) :: {:ok, map()} | {:error, term()}
  def analyze_conversation(agent) do
    case ToolIntegrationManager.get_conversation_history(agent.conversation_id) do
      {:ok, history} ->
        analysis = %{
          message_timeline: build_timeline(history),
          tool_usage: analyze_tool_usage(history),
          conversation_flow: analyze_flow(history),
          avg_response_time: calculate_avg_response_time(history)
        }

        {:ok, analysis}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Destroys the agent and cleans up resources.
  """
  @spec destroy_agent(agent()) :: :ok
  def destroy_agent(agent) do
    ToolIntegrationManager.end_conversation(agent.conversation_id)
  end

  # Private Functions - Core Logic

  defp process_with_retry(agent, message, retries) when retries > 0 do
    case ToolIntegrationManager.continue_conversation(agent.conversation_id, message) do
      {:ok, response} ->
        {:ok, response}

      {:error, {:tool_execution_failed, _reason}} ->
        Logger.warning("Tool execution failed, continuing with partial results")
        # In production, might return partial response
        {:error, :tool_execution_failed}

      {:error, {:llm_request_failed, reason}} ->
        Logger.warning("LLM request failed, retrying: #{inspect(reason)}")
        :timer.sleep(1000)
        process_with_retry(agent, message, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_with_retry(_agent, _message, 0) do
    {:error, :max_retries_exceeded}
  end

  # Private Functions - Scenario Runners

  defp run_scenarios(agent) do
    scenarios = [
      {"Weather + Calculation",
       "What's the weather in Paris? Also calculate the temperature in Fahrenheit if it's 18 Celsius."},
      {"Search + Weather",
       "Search for the capital of Japan, then tell me the weather there."},
      {"Complex Calculation", "Calculate (15 * 23) + (100 / 4) - 12"},
      {"Error Handling", "Get weather for InvalidCity123 and handle the error gracefully"}
    ]

    IO.puts(String.duplicate("-", 70))
    IO.puts("\n🎯 **Running Conversation Scenarios**\n")

    scenarios
    |> Enum.with_index(1)
    |> Enum.each(fn {{scenario_name, message}, idx} ->
      run_scenario(agent, idx, scenario_name, message)
      Process.sleep(500)
    end)
  end

  defp run_scenario(agent, number, scenario_name, message) do
    IO.puts("📍 **Scenario #{number}: #{scenario_name}**")
    IO.puts("   User: #{message}\n")

    start_time = System.monotonic_time(:millisecond)

    case process(agent, message, log: false) do
      {:ok, response, _updated_agent} ->
        duration = System.monotonic_time(:millisecond) - start_time

        display_scenario_response(response, duration)

      {:error, reason} ->
        IO.puts("   ❌ Error: #{inspect(reason)}\n")
    end
  end

  defp display_scenario_response(response, duration) do
    content = Map.get(response, :content, "")
    tool_calls = Map.get(response, :tool_calls, [])

    if content != "" do
      preview =
        if String.length(content) > 100 do
          String.slice(content, 0, 100) <> "..."
        else
          content
        end

      IO.puts("   🤖 Assistant: #{preview}")
    end

    if length(tool_calls) > 0 do
      IO.puts("   🔧 Tools Used: #{length(tool_calls)}")

      Enum.each(tool_calls, fn tool_call ->
        function = Map.get(tool_call, :function, %{})
        name = Map.get(function, :name, "unknown")
        IO.puts("      • #{name}")
      end)
    end

    IO.puts("   ⏱️  Duration: #{duration}ms\n")
  end

  # Private Functions - Display

  defp display_agent_info(agent) do
    IO.puts("✓ Agent created successfully\n")
    IO.puts("   ID: #{String.slice(agent.conversation_id, 0, 16)}...")
    IO.puts("   Tools: #{length(agent.tools)}")

    Enum.each(agent.tools, fn tool ->
      IO.puts("      • #{get_tool_name(tool)}")
    end)

    IO.puts("   Model: #{agent.options.model}")
    IO.puts("   Temperature: #{agent.options.temperature}")
    IO.puts("   Max Tool Calls: #{agent.options.max_tool_calls}")
    IO.puts("   Timeout: #{agent.options.timeout}ms\n")
  end

  defp display_final_statistics(agent) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("\n📊 **Final Statistics**\n")

    case get_statistics(agent) do
      {:ok, stats} ->
        IO.puts("   Conversation Age: #{stats.age_minutes} minutes")
        IO.puts("   Total Messages: #{stats.total_messages}")
        IO.puts("      • User: #{stats.user_messages}")
        IO.puts("      • Assistant: #{stats.assistant_messages}")
        IO.puts("      • Tool: #{stats.tool_messages}")
        IO.puts("   Tools Available: #{stats.tools_available}")

        # Display conversation analysis
        case analyze_conversation(agent) do
          {:ok, analysis} ->
            display_analysis(analysis)

          {:error, _} ->
            :ok
        end

      {:error, reason} ->
        IO.puts("   ❌ Error retrieving statistics: #{inspect(reason)}")
    end
  end

  defp display_analysis(analysis) do
    IO.puts("\n📈 **Conversation Analysis:**")

    tool_usage = Map.get(analysis, :tool_usage, %{})

    if map_size(tool_usage) > 0 do
      IO.puts("\n   Tool Usage Breakdown:")

      Enum.each(tool_usage, fn {tool_name, count} ->
        IO.puts("      • #{tool_name}: #{count} calls")
      end)
    end

    avg_time = Map.get(analysis, :avg_response_time, 0)

    if avg_time > 0 do
      IO.puts("\n   Avg Response Time: #{Float.round(avg_time, 1)}s")
    end
  end

  # Private Functions - Analysis

  defp count_messages_by_role(history, role) do
    Enum.count(history, fn msg -> Map.get(msg, :role) == role end)
  end

  defp get_tool_name(tool_module) do
    # Try to get the name from the module
    try do
      tool_module.name()
    rescue
      _ -> inspect(tool_module)
    end
  end

  defp build_timeline(history) do
    Enum.map(history, fn msg ->
      %{
        role: Map.get(msg, :role),
        timestamp: Map.get(msg, :timestamp),
        has_content: Map.get(msg, :content, "") != ""
      }
    end)
  end

  defp analyze_tool_usage(history) do
    history
    |> Enum.filter(fn msg -> Map.get(msg, :role) == "tool" end)
    |> Enum.reduce(%{}, fn msg, acc ->
      tool_name = get_in(msg, [:metadata, :tool_name]) || "unknown"
      Map.update(acc, tool_name, 1, &(&1 + 1))
    end)
  end

  defp analyze_flow(history) do
    # Analyze conversation flow patterns
    history
    |> Enum.map(& &1.role)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.frequencies()
  end

  defp calculate_avg_response_time(history) do
    # Calculate average time between user message and assistant response
    history
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [msg1, msg2] ->
      Map.get(msg1, :role) == "user" and Map.get(msg2, :role) == "assistant"
    end)
    |> Enum.map(fn [msg1, msg2] ->
      DateTime.diff(msg2.timestamp, msg1.timestamp, :millisecond)
    end)
    |> case do
      [] -> 0
      times -> Enum.sum(times) / length(times) / 1000
    end
  end
end

# Mock Actions for demonstration

defmodule Examples.ConversationManager.MockWeatherAction do
  @moduledoc "Mock weather action"

  use Jido.Action,
    name: "get_weather",
    description: "Get weather for a location",
    schema: [
      location: [type: :string, required: true]
    ]

  @impl true
  def run(params, _context) do
    location = params.location

    # Simulate different responses
    weather =
      case String.downcase(location) do
        loc when loc in ["paris", "france"] ->
          %{temp: 18, condition: "Cloudy", humidity: 65}

        loc when loc in ["tokyo", "japan"] ->
          %{temp: 22, condition: "Clear", humidity: 50}

        "invalidcity123" ->
          {:error, :location_not_found}

        _ ->
          %{temp: 20, condition: "Partly cloudy", humidity: 60}
      end

    case weather do
      {:error, reason} -> {:error, reason}
      data -> {:ok, Map.put(data, :location, location)}
    end
  end
end

defmodule Examples.ConversationManager.MockCalculatorAction do
  @moduledoc "Mock calculator action"

  use Jido.Action,
    name: "calculate",
    description: "Perform mathematical calculations",
    schema: [
      expression: [type: :string, required: true]
    ]

  @impl true
  def run(params, _context) do
    expression = params.expression

    # Simulate calculation
    result =
      cond do
        expression =~ ~r/\*/ ->
          # Simple multiplication example
          parse_and_multiply(expression)

        expression =~ ~r/\+/ ->
          # Simple addition
          parse_and_add(expression)

        true ->
          {:error, :unsupported_operation}
      end

    case result do
      {:error, reason} -> {:error, reason}
      value -> {:ok, %{expression: expression, result: value}}
    end
  end

  defp parse_and_multiply(expr) do
    case String.split(expr, "*") |> Enum.map(&String.trim/1) do
      [a, b] ->
        with {num1, _} <- Float.parse(a),
             {num2, _} <- Float.parse(b) do
          num1 * num2
        else
          _ -> {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end

  defp parse_and_add(expr) do
    case String.split(expr, "+") |> Enum.map(&String.trim/1) do
      [a, b] ->
        with {num1, _} <- Float.parse(a),
             {num2, _} <- Float.parse(b) do
          num1 + num2
        else
          _ -> {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end
end

defmodule Examples.ConversationManager.MockSearchAction do
  @moduledoc "Mock search action"

  use Jido.Action,
    name: "search",
    description: "Search for information",
    schema: [
      query: [type: :string, required: true]
    ]

  @impl true
  def run(params, _context) do
    query = String.downcase(params.query)

    # Simulate search results
    results =
      cond do
        query =~ ~r/capital.*japan/ ->
          [%{title: "Tokyo - Capital of Japan", snippet: "Tokyo is the capital city of Japan"}]

        query =~ ~r/weather/ ->
          [%{title: "Weather Services", snippet: "Check current weather conditions"}]

        true ->
          [%{title: "Search Results", snippet: "General results for: #{params.query}"}]
      end

    {:ok, %{query: params.query, results: results, count: length(results)}}
  end
end
