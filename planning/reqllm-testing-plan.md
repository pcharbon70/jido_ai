# ReqLLM Bridge Integration Testing Plan

**Date Created:** October 20, 2025
**Branch:** feature/integrate_req_llm
**Status:** Planning Complete - Ready for Implementation

---

## Executive Summary

This document outlines a comprehensive testing plan for the ReqLLM bridge functionality added in this branch. The plan focuses on testing the bridge layer components without testing actual LLM model integration, following the principle of testing interfaces and transformations rather than external dependencies.

**Objective**: Create simple, cohesive tests for the ReqLLM bridge functionality, ensuring all bridge components work correctly in isolation and in integration.

**Scope Exclusions**:
- ❌ LLM model integration with JidoAI
- ❌ JidoAI ↔ ReqLLM model transformation (assumed working)
- ❌ Actual API calls to LLM providers

**Testing Strategy**: Unit tests for each bridge module + integration tests for module interactions

---

## Architecture Overview

The ReqLLM integration adds the following bridge components:

```
┌─────────────────────────────────────────────────────────────┐
│                    JidoAI Application                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  ReqLlmBridge (Main)                         │
│  - Message conversion                                        │
│  - Response transformation                                   │
│  - Error mapping                                            │
│  - Tool conversion interface                                │
└─────────────────────────────────────────────────────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│Authentication│  │  ToolBuilder │  │ Conversation │
│              │  │              │  │   Manager    │
└──────────────┘  └──────────────┘  └──────────────┘
          │                 │                 │
          │                 ▼                 │
          │        ┌──────────────┐          │
          │        │ ToolExecutor │          │
          │        └──────────────┘          │
          │                                   │
          └─────────────────┬─────────────────┘
                            │
                            ▼
          ┌─────────────────────────────────┐
          │     Supporting Modules          │
          │  - StreamingAdapter             │
          │  - ResponseAggregator           │
          │  - ErrorHandler                 │
          │  - ParameterConverter           │
          │  - SchemaValidator              │
          └─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      ReqLLM Library                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 0. Doctest Strategy

### Overview

Doctests are tests embedded in module documentation using the `iex>` syntax. They serve dual purposes:
1. **Executable Documentation** - Examples in documentation that actually work
2. **Basic Functionality Tests** - Quick verification that core use cases work

### When to Use Doctests

**✅ Use doctests for:**
- Public API functions with simple, standalone examples
- Common use cases that don't require complex setup
- Examples that demonstrate typical usage
- Functions with straightforward inputs and outputs
- Quick verification that the module loads and basic functions work

**❌ Don't use doctests for:**
- Functions requiring complex setup (use regular tests instead)
- Functions with side effects (GenServer calls, ETS operations, etc.)
- Error cases (better tested in dedicated test files)
- Integration scenarios (use integration tests)
- Functions that need mocking

### Modules That Should Have Doctests

#### High Priority (Simple utility functions)

- [ ] **ReqLlmBridge (Main Module)**
  - `convert_messages/1` - Message format conversion
  - `convert_response/1` - Response transformation
  - `map_tool_choice_parameters/1` - Tool choice mapping
  - `build_req_llm_options/1` - Options building

- [ ] **ErrorHandler**
  - `format_error/1` - Error formatting examples
  - `categorize_error_type/1` - Error categorization
  - `sanitize_error_for_logging/1` - Sanitization examples

- [ ] **ToolBuilder**
  - `create_tool_descriptor/2` - Tool conversion examples
  - `validate_action_compatibility/1` - Validation examples

- [ ] **ResponseAggregator**
  - `format_for_user/2` - User formatting examples
  - `extract_metrics/1` - Metrics extraction

#### Medium Priority (Functions with simple examples)

- [ ] **ToolExecutor**
  - `create_callback/2` - Callback creation (if example doesn't require execution)

- [ ] **StreamingAdapter**
  - `continue_stream?/1` - Stream continuation logic

#### Low Priority (Mostly GenServer/stateful operations)

- **Authentication** - Skip (requires session/env setup)
- **ConversationManager** - Skip (GenServer state, complex setup)

### Doctest Guidelines

#### Structure
```elixir
@doc """
Brief description of the function.

## Parameters
  - param1: Description
  - param2: Description

## Returns
  - Return value description

## Examples

    iex> alias Jido.AI.ReqLlmBridge
    iex> ReqLlmBridge.convert_messages([%{role: :user, content: "Hello"}])
    "Hello"

    iex> messages = [
    ...>   %{role: :user, content: "Hi"},
    ...>   %{role: :assistant, content: "Hello!"}
    ...> ]
    iex> ReqLlmBridge.convert_messages(messages)
    [%{role: :user, content: "Hi"}, %{role: :assistant, content: "Hello!"}]
"""
```

#### Best Practices

1. **Keep Examples Simple**
   - One or two examples per function
   - Focus on the most common use case
   - Avoid complex setup

2. **Make Examples Self-Contained**
   - Include all necessary aliases
   - Define all data inline
   - Don't depend on external state

3. **Use Realistic Data**
   - Use realistic parameter values
   - Show actual return values, not placeholders
   - Demonstrate real-world usage

4. **Pattern Match Carefully**
   - Use exact matches for simple values
   - Use pattern matching for complex structures
   - Consider using `assert` in regular tests for complex assertions

5. **Handle Multi-Line Examples**
   - Use `...>` for continuation lines
   - Keep formatting consistent
   - Group related lines together

### Implementation Checklist

- [ ] Add doctests to ReqLlmBridge main module (8 functions)
- [ ] Add doctests to ErrorHandler (3-4 functions)
- [ ] Add doctests to ToolBuilder (2-3 functions)
- [ ] Add doctests to ResponseAggregator (2 functions)
- [ ] Add doctests to ToolExecutor (1 function)
- [ ] Add doctests to StreamingAdapter (1 function)
- [ ] Configure test_helper.exs to run doctests:
  ```elixir
  # In test/test_helper.exs
  # Ensure doctests are included in test runs
  ExUnit.start()
  ```
- [ ] Verify all doctests pass with `mix test --only doctest`

### Expected Doctest Count

**Total Doctests: ~20-25 examples**
- ReqLlmBridge: 8-10 examples
- ErrorHandler: 4-5 examples
- ToolBuilder: 3-4 examples
- ResponseAggregator: 2-3 examples
- ToolExecutor: 1-2 examples
- StreamingAdapter: 1 example

### Benefits

✅ **Documentation Quality**
- Examples are guaranteed to work
- Documentation stays up-to-date with code
- New developers can trust the examples

✅ **Quick Feedback**
- Catch breaking changes in public APIs
- Verify module loads correctly
- Fast-running basic smoke tests

✅ **Reduced Test Duplication**
- Examples serve as both docs and tests
- Less need for trivial test cases
- Focus regular tests on edge cases and complex scenarios

---

## 1. Authentication Module Tests ✅

**Module**: `Jido.AI.ReqLlmBridge.Authentication`
**File**: `lib/jido_ai/req_llm_bridge/authentication.ex`
**Test File**: `test/jido_ai/req_llm_bridge/authentication_test.exs`
**Status**: COMPLETED (11 tests passing)
**Date Completed**: October 20, 2025

### Overview

Test the provider authentication system and session-based precedence. The Authentication module bridges Jido's session-based authentication with ReqLLM's provider-specific authentication, supporting multiple providers with different header formats.

**Implementation Note**: Tests focus on session-based authentication (highest precedence) which provides reliable, testable behavior. Full integration with ReqLLM.Keys delegation is covered by integration tests.

### Tasks:

#### [x] 1.1 Provider Authentication Mapping

Test that each provider gets correctly formatted authentication headers.

- [x] **Test OpenAI authentication header formatting**
  - Assert `"authorization"` header with `"Bearer "` prefix
  - Assert no additional headers for OpenAI

- [x] **Test Anthropic authentication with version header**
  - Assert `"x-api-key"` header with no prefix
  - Assert `"anthropic-version"` header is `"2023-06-01"`

- [x] **Test OpenRouter, Google, Cloudflare providers**
  - OpenRouter: `"authorization"` with `"Bearer "` prefix
  - Google: `"x-goog-api-key"` with no prefix
  - Cloudflare: `"x-auth-key"` with no prefix

- [~] **Test unknown provider fallback to generic format**
  - Note: Deferred to integration tests (covered indirectly)

#### [x] 1.2 Session-based Authentication

Test session-based authentication behavior (highest precedence).

- [x] **Test session value is used for authentication**
  - Set session key via `Keyring.set_session_value/3`
  - Assert session key is used in headers

- [x] **Test different providers use their session keys independently**
  - Set different keys for multiple providers
  - Assert each provider uses correct key and headers

- [x] **Test error when no session key is set**
  - Don't set session keys
  - Assert `{:error, reason}` with appropriate message

#### [x] 1.3 Authentication Validation

Test the validation logic for authentication availability.

- [x] **Test validation succeeds with valid key**
  - Set valid API key via session
  - Assert `validate_authentication(:openai, opts)` returns `:ok`

- [x] **Test validation fails with missing key**
  - Clear all authentication sources
  - Assert `{:error, reason}` with appropriate message

- [x] **Test validation works for multiple providers**
  - Set keys for multiple providers
  - Assert all validate successfully

### Bugs Fixed

During implementation, discovered and fixed critical bugs in `Authentication.ex`:

- **Line 289**: Fixed `Keyring.get_env_value(:default, ...)` → `Keyring.get_env_value(Jido.AI.Keyring, ...)`
- **Line 340**: Fixed `Keyring.get_env_value(:default, ...)` → `Keyring.get_env_value(Jido.AI.Keyring, ...)`

These bugs would have caused GenServer crashes when falling back to Keyring authentication.

---

## 2. ToolExecutor Module Tests

**Module**: `Jido.AI.ReqLlmBridge.ToolExecutor`
**File**: `lib/jido_ai/req_llm_bridge/tool_executor.ex`
**Test File**: `test/jido_ai/req_llm_bridge/tool_executor_test.exs`

### Overview

Test safe tool execution with parameter validation, timeout protection, and comprehensive error handling. The ToolExecutor is responsible for executing Jido Actions as ReqLLM tool callbacks.

### Tasks:

#### [ ] 2.1 Basic Tool Execution

Test successful execution flow with valid inputs.

- [ ] **Test successful tool execution with valid params**
  - Use a simple test Action (e.g., `Jido.Actions.Basic.Sleep`)
  - Pass valid parameters
  - Assert `{:ok, result}` with serializable result

- [ ] **Test execution timeout protection**
  - Mock an Action that sleeps longer than timeout
  - Set short timeout (e.g., 100ms)
  - Assert `{:error, %{type: "execution_timeout"}}`

- [ ] **Test callback function creation**
  - Create callback with `create_callback/2`
  - Assert callback is a function
  - Assert callback accepts 1 argument (params)
  - Execute callback and verify result

#### [ ] 2.2 Parameter Validation

Test parameter conversion and validation against Action schemas.

- [ ] **Test parameter conversion from JSON to Jido format**
  - Pass JSON params with string keys: `%{"duration_ms" => 100}`
  - Assert converted to atom keys: `%{duration_ms: 100}`
  - Assert parameter types are preserved

- [ ] **Test parameter validation against Action schema**
  - Use Action with required parameters
  - Pass missing required parameter
  - Assert `{:error, %{type: "parameter_validation_error"}}`

- [ ] **Test parameter validation error formatting**
  - Trigger validation error
  - Assert error includes field name
  - Assert error includes validation details

#### [ ] 2.3 Error Handling

Test comprehensive error handling and conversion.

- [ ] **Test execution exception catching and formatting**
  - Mock an Action that raises an exception
  - Assert `{:error, %{type: "exception"}}`
  - Assert error includes exception message
  - Assert error includes stacktrace

- [ ] **Test JSON serialization error handling**
  - Mock an Action that returns non-serializable result (e.g., PID)
  - Assert result is sanitized to string representation
  - Assert `serialization_fallback: true` flag is set

- [ ] **Test sanitization of non-serializable results**
  - Test with PID: assert `inspect(pid)` format
  - Test with reference: assert `inspect(ref)` format
  - Test with function: assert `inspect(fn)` format
  - Test with port: assert `inspect(port)` format
  - Test with struct: assert converted to map

#### [ ] 2.4 Circuit Breaker (Simplified)

Test circuit breaker placeholder implementation.

- [ ] **Test circuit breaker status check returns :closed**
  - Call `execute_with_circuit_breaker/4`
  - Assert circuit breaker status is `:closed`
  - Assert execution proceeds normally

---

## 3. ToolBuilder Module Tests

**Module**: `Jido.AI.ReqLlmBridge.ToolBuilder`
**File**: `lib/jido_ai/req_llm_bridge/tool_builder.ex`
**Test File**: `test/jido_ai/req_llm_bridge/tool_builder_test.exs`

### Overview

Test Action-to-tool descriptor conversion system. The ToolBuilder validates Actions, converts schemas from NimbleOptions to JSON Schema format, and creates callback functions for ReqLLM.

### Tasks:

#### [ ] 3.1 Tool Descriptor Creation

Test successful descriptor creation from valid Actions.

- [ ] **Test successful descriptor creation from valid Action**
  - Use `Jido.Actions.Basic.Sleep`
  - Assert descriptor has `:name`, `:description`, `:parameter_schema`, `:callback`
  - Assert all fields are non-nil

- [ ] **Test tool name extraction from Action**
  - Action with `name/0` function: assert uses that name
  - Action without `name/0`: assert uses underscored module name

- [ ] **Test tool description extraction from Action**
  - Action with `description/0`: assert uses that description
  - Action without `description/0`: assert uses "No description provided"

- [ ] **Test schema conversion from NimbleOptions to JSON Schema**
  - Define Action with NimbleOptions schema
  - Assert converted schema has JSON Schema structure
  - Assert required fields are identified
  - Assert types are converted correctly

#### [ ] 3.2 Action Validation

Test validation logic for Action module compatibility.

- [ ] **Test validation succeeds for valid Action module**
  - Use `Jido.Actions.Basic.Sleep`
  - Assert `validate_action_compatibility/1` returns `:ok`

- [ ] **Test validation fails for non-loaded module**
  - Use non-existent module atom
  - Assert `{:error, %{reason: "module_not_loaded"}}`

- [ ] **Test validation fails for module without `__action_metadata__/0`**
  - Create module without Action behavior
  - Assert `{:error, %{reason: "invalid_action_module"}}`

- [ ] **Test validation fails for module without `run/2`**
  - Create module with `__action_metadata__/0` but no `run/2`
  - Assert `{:error, %{reason: "missing_run_function"}}`

#### [ ] 3.3 Batch Conversion

Test converting multiple Actions in a single operation.

- [ ] **Test successful batch conversion of multiple Actions**
  - Pass list of valid Actions
  - Assert `{:ok, descriptors}` with all descriptors
  - Assert descriptor count matches input count

- [ ] **Test partial success when some Actions fail**
  - Pass mix of valid and invalid Actions
  - Assert `{:ok, descriptors}` with only valid conversions
  - Assert warning is logged for failures

- [ ] **Test error when all conversions fail**
  - Pass list of all invalid Actions
  - Assert `{:error, %{reason: "all_conversions_failed"}}`
  - Assert error includes failure details

---

## 4. StreamingAdapter Module Tests

**Module**: `Jido.AI.ReqLlmBridge.StreamingAdapter`
**File**: `lib/jido_ai/req_llm_bridge/streaming_adapter.ex`
**Test File**: `test/jido_ai/req_llm_bridge/streaming_adapter_test.exs`

### Overview

Test streaming response transformation and lifecycle management. The StreamingAdapter handles chunk-by-chunk processing of streaming responses, adding metadata, and managing stream lifecycle.

### Tasks:

#### [ ] 4.1 Chunk Transformation

Test chunk transformation with metadata enrichment.

- [ ] **Test chunk transformation with metadata enrichment**
  - Create mock chunk: `%{content: "Hello", finish_reason: nil}`
  - Transform with `transform_chunk_with_metadata/1`
  - Assert result includes `:chunk_metadata` with `:index`, `:timestamp`, `:chunk_size`, `:provider`

- [ ] **Test chunk content extraction**
  - Test with `:content` key
  - Test with `"content"` string key
  - Test with `:text` key
  - Test with nested `:delta` > `:content`
  - Assert all variations extract content correctly

- [ ] **Test provider extraction from chunk**
  - Test with `:provider` key
  - Test with `:model` key
  - Assert fallback to "unknown" when not present

#### [ ] 4.2 Stream Lifecycle

Test stream continuation logic based on finish reasons.

- [ ] **Test continue_stream? detects finish_reason: "stop"**
  - Create chunk with `finish_reason: "stop"`
  - Assert `continue_stream?/1` returns `false`

- [ ] **Test continue_stream? continues on finish_reason: nil**
  - Create chunk with `finish_reason: nil`
  - Assert `continue_stream?/1` returns `true`

- [ ] **Test stream continues without definitive stop condition**
  - Test with `finish_reason: ""`
  - Test with `finish_reason: "unknown"`
  - Assert both return `true`

#### [ ] 4.3 Error Recovery

Test error handling in streaming contexts.

- [ ] **Test error recovery continues stream (when enabled)**
  - Create stream that throws error mid-stream
  - Enable error recovery
  - Assert stream continues after error
  - Assert error is logged

- [ ] **Test error terminates stream (when recovery disabled)**
  - Create stream that throws error
  - Disable error recovery
  - Assert error is thrown and stream terminates

---

## 5. ConversationManager Module Tests

**Module**: `Jido.AI.ReqLlmBridge.ConversationManager`
**File**: `lib/jido_ai/req_llm_bridge/conversation_manager.ex`
**Test File**: `test/jido_ai/req_llm_bridge/conversation_manager_test.exs`

### Overview

Test stateful conversation management with ETS storage. The ConversationManager maintains conversation state, message history, tool configurations, and metadata using ETS tables for fast in-memory storage.

### Setup

```elixir
setup do
  # Start ConversationManager if not already started
  case GenServer.whereis(ConversationManager) do
    nil -> start_supervised!(ConversationManager)
    _pid -> :ok
  end

  # Clear all conversations before each test
  :ok = ConversationManager.clear_all_conversations()

  :ok
end
```

### Tasks:

#### [ ] 5.1 Conversation Lifecycle

Test creating, ending, and listing conversations.

- [ ] **Test conversation creation generates unique ID**
  - Create conversation with `create_conversation/0`
  - Assert `{:ok, conv_id}` with non-empty string ID
  - Create second conversation
  - Assert second ID is different from first

- [ ] **Test conversation ending removes from storage**
  - Create conversation
  - End conversation with `end_conversation/1`
  - Assert conversation no longer in list
  - Assert getting conversation returns error

- [ ] **Test listing active conversations**
  - Create 3 conversations
  - Assert `list_conversations/0` returns all 3 IDs
  - End 1 conversation
  - Assert list now has 2 IDs

#### [ ] 5.2 Message Management

Test adding and retrieving messages in conversation history.

- [ ] **Test adding user messages to history**
  - Create conversation
  - Add user message: `add_user_message/3`
  - Get history
  - Assert message in history with role: "user"

- [ ] **Test adding assistant responses to history**
  - Create conversation
  - Add assistant response: `add_assistant_response/3`
  - Get history
  - Assert message in history with role: "assistant"
  - Assert metadata includes tool_calls, usage, model

- [ ] **Test adding tool results to history**
  - Create conversation
  - Add tool results: `add_tool_results/3`
  - Get history
  - Assert messages in history with role: "tool"
  - Assert metadata includes tool_call_id, tool_name

- [ ] **Test retrieving complete conversation history**
  - Create conversation
  - Add user message, assistant response, tool results
  - Get history
  - Assert messages in chronological order
  - Assert all messages have timestamps

#### [ ] 5.3 Tool Configuration

Test setting and retrieving tool configurations per conversation.

- [ ] **Test setting tools for conversation**
  - Create conversation
  - Set tools: `set_tools/2`
  - Assert `:ok`

- [ ] **Test getting tools for conversation**
  - Create conversation and set tools
  - Get tools: `get_tools/1`
  - Assert `{:ok, tools}` with correct tools

- [ ] **Test finding tool by name**
  - Create conversation with multiple tools
  - Find tool: `find_tool_by_name/2`
  - Assert `{:ok, tool}` when found
  - Assert `{:error, :not_found}` when not found

#### [ ] 5.4 Options Management

Test setting and retrieving conversation-specific options.

- [ ] **Test setting conversation options (model, temperature, etc.)**
  - Create conversation
  - Set options: `set_options/2` with model, temperature, max_tokens
  - Assert `:ok`

- [ ] **Test getting conversation options**
  - Create conversation and set options
  - Get options: `get_options/1`
  - Assert `{:ok, options}` with correct values

#### [ ] 5.5 Metadata

Test conversation metadata tracking.

- [ ] **Test conversation metadata includes creation time**
  - Create conversation
  - Get metadata: `get_conversation_metadata/1`
  - Assert metadata includes `:created_at` timestamp

- [ ] **Test metadata includes message count**
  - Create conversation
  - Add 3 messages
  - Get metadata
  - Assert `:message_count` is 3

- [ ] **Test last_activity updates on message add**
  - Create conversation
  - Get initial metadata
  - Wait 100ms
  - Add message
  - Get updated metadata
  - Assert `:last_activity` is later than initial

---

## 6. ResponseAggregator Module Tests

**Module**: `Jido.AI.ReqLlmBridge.ResponseAggregator`
**File**: `lib/jido_ai/req_llm_bridge/response_aggregator.ex`
**Test File**: `test/jido_ai/req_llm_bridge/response_aggregator_test.exs`

### Overview

Test response aggregation and formatting. The ResponseAggregator combines LLM responses with tool execution results, normalizes content, and provides user-friendly formatting.

### Tasks:

#### [ ] 6.1 Content Aggregation

Test extracting and normalizing content from various formats.

- [ ] **Test extracting base content from response**
  - Test with `:content` key
  - Test with `"content"` string key
  - Test with `:text` key
  - Test with `:message` key
  - Assert all variations extract content

- [ ] **Test extracting content from content array**
  - Create response with content array:
    ```elixir
    %{content: [%{type: "text", text: "Hello"}, %{type: "text", text: " world"}]}
    ```
  - Assert extracted content is `"Hello world"`

- [ ] **Test normalizing content arrays to strings**
  - Create mixed content array
  - Assert all text items are joined
  - Assert non-text items are skipped

- [ ] **Test handling empty content**
  - Test with `content: ""`
  - Test with `content: []`
  - Assert fallback message is used

#### [ ] 6.2 Tool Result Integration

Test extracting and integrating tool results.

- [ ] **Test extracting tool calls from response**
  - Create response with `:tool_calls` array
  - Assert extracted tool calls preserve structure

- [ ] **Test extracting tool results from response**
  - Create response with `:tool_results` array
  - Assert extracted tool results preserve structure

- [ ] **Test integrating tool results into content**
  - Create response with content and tool results
  - Format for user with integrated style
  - Assert tool results are integrated into narrative

#### [ ] 6.3 Usage Statistics

Test extracting and aggregating usage statistics.

- [ ] **Test extracting usage stats (prompt_tokens, completion_tokens, total_tokens)**
  - Create response with usage stats
  - Extract usage
  - Assert all token counts are present

- [ ] **Test merging usage stats from streaming chunks**
  - Create 3 chunks with different usage stats
  - Merge stats
  - Assert totals are summed correctly

#### [ ] 6.4 Response Formatting

Test formatting responses for user consumption.

- [ ] **Test formatting response for user (integrated style)**
  - Create aggregated response
  - Format with `tool_result_style: :integrated`
  - Assert tool results are integrated into content

- [ ] **Test formatting response for user (appended style)**
  - Create aggregated response
  - Format with `tool_result_style: :appended`
  - Assert tool results are appended after content

- [ ] **Test formatting with metadata included**
  - Format with `include_metadata: true`
  - Assert metadata section is present
  - Assert includes processing time, tokens, tools executed

#### [ ] 6.5 Metrics Extraction

Test extracting analytics metrics from responses.

- [ ] **Test extracting processing time metrics**
  - Create response with metadata
  - Extract metrics
  - Assert `:processing_time_ms` is present

- [ ] **Test extracting tool execution statistics**
  - Create response with tool results
  - Extract metrics
  - Assert `:tools_executed` count is correct
  - Assert `:tools_successful` count is correct
  - Assert `:tools_failed` count is correct

- [ ] **Test calculating tool success rate**
  - 3 successful, 1 failed tool
  - Assert success rate is 75.0

---

## 7. ErrorHandler Module Tests

**Module**: `Jido.AI.ReqLlmBridge.ErrorHandler`
**File**: `lib/jido_ai/req_llm_bridge/error_handler.ex`
**Test File**: `test/jido_ai/req_llm_bridge/error_handler_test.exs`

### Overview

Test centralized error handling and formatting. The ErrorHandler provides consistent error formatting, categorization, and sensitive data sanitization across all bridge components.

### Tasks:

#### [ ] 7.1 Error Formatting

Test formatting various error types into standardized structure.

- [ ] **Test formatting validation errors**
  - Format `{:validation_error, "name", "required"}`
  - Assert result has `:type`, `:field`, `:message`, `:category`
  - Assert category is `"parameter_error"`

- [ ] **Test formatting parameter errors**
  - Format `{:parameter_validation_error, "age", "must be positive"}`
  - Assert correct structure
  - Assert category is `"parameter_error"`

- [ ] **Test formatting execution errors**
  - Format `{:action_execution_error, "timeout"}`
  - Assert category is `"execution_error"`

- [ ] **Test formatting timeout errors**
  - Format `{:execution_timeout, 5000}`
  - Assert message includes timeout value
  - Assert category is `"execution_error"`

- [ ] **Test formatting serialization errors**
  - Format `{:serialization_error, "invalid JSON"}`
  - Assert category is `"serialization_error"`

#### [ ] 7.2 Error Categorization

Test categorizing errors into logical groups.

- [ ] **Test categorizing parameter errors**
  - Categorize "validation_error"
  - Assert category is `"parameter_error"`

- [ ] **Test categorizing execution errors**
  - Categorize "timeout"
  - Categorize "execution_exception"
  - Assert category is `"execution_error"`

- [ ] **Test categorizing network errors**
  - Categorize "connection_error"
  - Categorize "transport_error"
  - Assert category is `"network_error"`

- [ ] **Test categorizing unknown errors**
  - Categorize "random_error"
  - Assert category is `"unknown_error"`

#### [ ] 7.3 Sensitive Data Sanitization

Test redacting sensitive information from errors.

- [ ] **Test redacting password fields**
  - Create error with `password: "secret123"`
  - Sanitize for logging
  - Assert password is `"[REDACTED]"`

- [ ] **Test redacting API key fields**
  - Create error with `api_key: "sk-12345"`
  - Sanitize for logging
  - Assert api_key is `"[REDACTED]"`

- [ ] **Test redacting token fields**
  - Create error with `token: "abc123"`
  - Sanitize for logging
  - Assert token is `"[REDACTED]"`

- [ ] **Test sanitizing sensitive patterns in strings**
  - Create error message: `"Authentication failed with password=secret123"`
  - Sanitize string
  - Assert password value is redacted

#### [ ] 7.4 Tool Error Responses

Test creating standardized tool error responses.

- [ ] **Test creating standardized tool error response**
  - Create tool error response with context
  - Assert response has `:error`, `:type`, `:message`, `:category`, `:timestamp`, `:context`
  - Assert `:error` is `true`

- [ ] **Test error response includes timestamp**
  - Create error response
  - Assert `:timestamp` is ISO8601 formatted string

- [ ] **Test error response sanitizes context**
  - Create error with sensitive context
  - Assert sensitive fields are removed from context

---

## 8. Main Bridge Module Tests

**Module**: `Jido.AI.ReqLlmBridge`
**File**: `lib/jido_ai/req_llm_bridge.ex`
**Test File**: `test/jido_ai/req_llm_bridge_test.exs`

### Overview

Test the main ReqLlmBridge utility functions. The main bridge module provides the public interface for message conversion, response transformation, error mapping, and integration with supporting modules.

### Tasks:

#### [ ] 8.1 Message Conversion

Test converting messages between Jido and ReqLLM formats.

- [ ] **Test converting single user message to string format**
  - Convert `[%{role: :user, content: "Hello"}]`
  - Assert result is string `"Hello"`

- [ ] **Test converting multi-turn conversation to message array**
  - Convert multiple messages with different roles
  - Assert result is array of message maps
  - Assert structure is preserved

- [ ] **Test message role preservation**
  - Convert messages with :user, :assistant, :system roles
  - Assert all roles are preserved in output

#### [ ] 8.2 Response Conversion

Test converting ReqLLM responses to Jido format.

- [ ] **Test converting ReqLLM response to Jido format**
  - Create ReqLLM-style response
  - Convert with `convert_response/1`
  - Assert result has `:content`, `:usage`, `:tool_calls`, `:finish_reason`

- [ ] **Test extracting usage from response**
  - Response with `:usage` key
  - Response with `"usage"` string key
  - Assert usage is extracted correctly

- [ ] **Test extracting tool_calls from response**
  - Response with `:tool_calls` array
  - Assert tool calls are converted to Jido format

- [ ] **Test extracting finish_reason from response**
  - Response with `:finish_reason`
  - Response with `"finish_reason"`
  - Assert finish reason is extracted

#### [ ] 8.3 Error Mapping

Test mapping ReqLLM errors to Jido error format.

- [ ] **Test mapping HTTP errors**
  - Map `{:error, %{status: 400, body: "Bad request"}}`
  - Assert mapped error has `:reason`, `:details`, `:status`, `:body`

- [ ] **Test mapping struct errors**
  - Map error with `__struct__` field
  - Assert mapped error preserves original error

- [ ] **Test mapping transport errors**
  - Map `Req.TransportError` exception
  - Assert mapped error has `:reason` = `"transport_error"`

- [ ] **Test mapping string errors**
  - Map `{:error, "Something went wrong"}`
  - Assert mapped error has `:reason` and `:details`

#### [ ] 8.4 Options Building

Test building ReqLLM options from Jido parameters.

- [ ] **Test building ReqLLM options from Jido params**
  - Pass params with temperature, max_tokens, top_p, stop
  - Assert all params are included in options
  - Assert nil params are filtered out

- [ ] **Test tool_choice parameter mapping (:auto, :none, :required)**
  - Map `:auto` → `"auto"`
  - Map `:none` → `"none"`
  - Map `:required` → `"required"`
  - Assert all standard choices work

- [ ] **Test specific function selection tool_choice**
  - Map `{:function, "my_tool"}` → `%{type: "function", function: %{name: "my_tool"}}`
  - Assert structure is correct

- [ ] **Test filtering nil values from options**
  - Pass params with nil values
  - Assert nil values are not in final options

#### [ ] 8.5 Tool Conversion Interface

Test the facade functions that delegate to ToolBuilder.

- [ ] **Test convert_tools/1 delegates to ToolBuilder**
  - Mock ToolBuilder
  - Call `convert_tools/1`
  - Assert ToolBuilder is called
  - Assert result is converted to ReqLLM tool format

- [ ] **Test convert_tools_with_options/2 passes options**
  - Call with options map
  - Assert options are passed to ToolBuilder

- [ ] **Test validate_tool_compatibility/1 delegates to ToolBuilder**
  - Call `validate_tool_compatibility/1`
  - Assert ToolBuilder validation is called

#### [ ] 8.6 Streaming Conversion

Test streaming chunk transformation.

- [ ] **Test transforming streaming chunks**
  - Create chunk: `%{content: "Hello", finish_reason: nil}`
  - Transform with `transform_streaming_chunk/1`
  - Assert result has `:content`, `:finish_reason`, `:usage`, `:tool_calls`, `:delta`

- [ ] **Test extracting chunk content**
  - Test with various content locations (`:content`, `:text`, `:delta` > `:content`)
  - Assert content is extracted correctly

- [ ] **Test extracting chunk delta**
  - Create chunk with content
  - Assert `:delta` includes `:content` and `:role`

#### [ ] 8.7 Provider Key Management

Test integration with Authentication module for key management.

- [ ] **Test get_provider_key/3 returns key from Authentication**
  - Mock Authentication
  - Call `get_provider_key/3`
  - Assert key is returned

- [ ] **Test get_provider_headers/2 returns formatted headers**
  - Call `get_provider_headers/2`
  - Assert headers are formatted correctly for provider

- [ ] **Test get_provider_authentication/2 returns both key and headers**
  - Call `get_provider_authentication/2`
  - Assert `{:ok, {key, headers}}` tuple is returned

- [ ] **Test validate_provider_key/1 checks availability**
  - Call `validate_provider_key/1` with valid provider
  - Assert `{:ok, source}` when key available
  - Assert `{:error, :missing_key}` when not available

- [ ] **Test list_available_providers/0 returns providers with keys**
  - Set keys for some providers
  - Call `list_available_providers/0`
  - Assert only providers with keys are returned

---

## 9. Integration Tests

**Test File**: `test/jido_ai/req_llm_bridge/integration_test.exs`

### Overview

Test interactions between modules to verify the complete system works end-to-end. Integration tests use real modules (not mocks) to test actual behavior across module boundaries.

### Tasks:

#### [ ] 9.1 Tool Conversion and Execution Flow

Test the complete flow from Action to tool descriptor to execution.

- [ ] **Test converting Action → tool descriptor → execution**
  - Convert `Jido.Actions.Basic.Sleep` to tool descriptor
  - Execute tool descriptor callback
  - Assert result matches expected output

- [ ] **Test parameter flow: JSON params → conversion → validation → Action.run**
  - Start with JSON params: `%{"duration_ms" => 100}`
  - Convert to tool descriptor
  - Execute callback
  - Assert Action.run receives correct params

- [ ] **Test result flow: Action result → serialization → tool result**
  - Execute Action that returns map
  - Assert result is JSON-serializable
  - Assert result format is correct

#### [ ] 9.2 Conversation with Tools

Test conversation management with tool execution.

- [ ] **Test creating conversation with tool configuration**
  - Create conversation
  - Set tools for conversation
  - Assert tools are stored correctly

- [ ] **Test adding messages to conversation**
  - Add user message
  - Add assistant response
  - Add tool results
  - Assert all messages in history

- [ ] **Test tool execution within conversation context**
  - Get tool from conversation
  - Execute tool with conversation context
  - Assert execution succeeds

- [ ] **Test conversation history includes tool results**
  - Execute tools in conversation
  - Get history
  - Assert tool results are in history

#### [ ] 9.3 Response Aggregation with Tools

Test combining LLM responses with tool execution results.

- [ ] **Test aggregating LLM response with tool execution results**
  - Create response with tool calls
  - Execute tools
  - Aggregate response
  - Assert tool results are integrated

- [ ] **Test combining content and tool results**
  - Create response with both content and tool results
  - Aggregate response
  - Assert both are included in final response

- [ ] **Test usage statistics aggregation**
  - Create response with usage stats
  - Aggregate response
  - Assert usage stats are preserved

#### [ ] 9.4 Authentication Integration

Test authentication flow with provider mapping and key resolution.

- [ ] **Test authentication flow with provider mapping**
  - Set provider key
  - Authenticate for provider
  - Assert correct headers are generated

- [ ] **Test building ReqLLM options with authenticated keys**
  - Build options for provider
  - Assert API key is included
  - Assert key comes from correct source

- [ ] **Test session-based authentication in tool execution context**
  - Set session key
  - Execute tool (which may need auth)
  - Assert session key is used

#### [ ] 9.5 Error Flow

Test error propagation through the system.

- [ ] **Test error propagation from tool execution → ErrorHandler → response**
  - Execute tool that throws error
  - Assert error is formatted by ErrorHandler
  - Assert error appears in final response

- [ ] **Test error sanitization in final response**
  - Create error with sensitive data
  - Assert sensitive data is redacted in final response

- [ ] **Test error categorization in aggregated response**
  - Create various error types
  - Aggregate response
  - Assert errors are correctly categorized in metadata

---

## 10. Success Criteria

### Required Outcomes

✅ **Authentication Tests** (13 tests)
- All authentication tests pass with correct header formatting
- Session precedence works correctly
- Provider mappings are accurate
- Validation logic is correct

✅ **ToolExecutor Tests** (11 tests)
- Tool execution succeeds with valid params
- Timeout protection works
- Parameter validation catches errors
- Error handling sanitizes all non-serializable types

✅ **ToolBuilder Tests** (10 tests)
- Tool descriptors created successfully from valid Actions
- Action validation catches all incompatibility cases
- Batch conversion handles partial failures correctly

✅ **StreamingAdapter Tests** (7 tests)
- Chunk transformation adds metadata correctly
- Stream lifecycle management works
- Error recovery behaves as configured

✅ **ConversationManager Tests** (13 tests)
- Conversation lifecycle (create, end, list) works
- Message history tracking is accurate
- Tool and options management works
- Metadata tracking is correct

✅ **ResponseAggregator Tests** (14 tests)
- Content extraction handles all formats
- Content normalization works (arrays → strings)
- Tool result integration is correct
- Usage statistics aggregation works
- Metrics extraction provides accurate analytics

✅ **ErrorHandler Tests** (12 tests)
- All error types formatted correctly
- Error categorization is accurate
- Sensitive data sanitization works
- Tool error responses have correct structure

✅ **Main Bridge Tests** (20 tests)
- Message conversion preserves structure
- Response conversion handles all formats
- Error mapping is comprehensive
- Options building filters and maps correctly
- Tool conversion interface delegates properly
- Streaming conversion works
- Provider key management integrates with Authentication

✅ **Integration Tests** (13 tests)
- Complete tool conversion and execution flow works
- Conversation with tools works end-to-end
- Response aggregation combines all parts correctly
- Authentication integrates throughout the system
- Errors propagate and sanitize correctly

✅ **Doctests** (20-25 examples)
- All doctests pass and demonstrate working examples
- ReqLlmBridge main module has working examples (8-10)
- ErrorHandler has working examples (4-5)
- ToolBuilder has working examples (3-4)
- ResponseAggregator has working examples (2-3)
- ToolExecutor has working examples (1-2)
- StreamingAdapter has working examples (1)
- All documentation examples are realistic and useful

### Quality Metrics

✅ **Test Suite Health**
- Total tests: ~113 unit tests + ~20-25 doctests + integration tests
- Test suite runs without memory issues (<500MB)
- Test suite completes in reasonable time (<2 minutes)
- All tests are isolated and can run independently
- No tests skip or are excluded
- Doctests can be run separately with `mix test --only doctest`

✅ **Code Quality**
- No production code changes needed (tests validate existing behavior)
- All tests use mocks/stubs for external dependencies (no real API calls)
- Clear test names describe what is being tested
- Test failures provide actionable error messages
- Tests follow ExUnit best practices

✅ **Coverage**
- All public functions have at least one test
- All error paths are tested
- All integration points between modules are tested
- Edge cases are covered (empty inputs, nil values, etc.)

---

## Implementation Guidelines

### Test File Organization

```
test/
├── jido_ai/
│   └── req_llm_bridge/
│       ├── authentication_test.exs              # 13 tests
│       ├── tool_executor_test.exs               # 11 tests
│       ├── tool_builder_test.exs                # 10 tests
│       ├── streaming_adapter_test.exs           # 7 tests
│       ├── conversation_manager_test.exs        # 13 tests
│       ├── response_aggregator_test.exs         # 14 tests
│       ├── error_handler_test.exs               # 12 tests
│       ├── integration_test.exs                 # 13 tests
│       └── req_llm_bridge_test.exs              # 20 tests (main bridge)
```

### Testing Approach

1. **Unit Tests First**
   - Start with module-level tests
   - Test each public function
   - Use mocks for dependencies
   - Focus on behavior, not implementation

2. **Integration Tests Second**
   - Test module interactions
   - Use real modules (no mocks for system modules)
   - Test complete workflows
   - Verify data flows correctly through system

3. **Mock Strategy**
   - Use Mimic for mocking
   - Mock external dependencies (ReqLLM, external APIs)
   - Don't mock system modules in integration tests
   - Stub callbacks when needed

4. **Test Naming Convention**
   ```elixir
   # Good
   test "extracts content from response with :content key"
   test "validates authentication succeeds with valid key"
   test "formats validation error with correct structure"

   # Bad
   test "test content extraction"
   test "auth validation"
   ```

5. **Setup and Teardown**
   ```elixir
   setup do
     # Start supervised processes if needed
     start_supervised!(ConversationManager)

     # Clear state before each test
     ConversationManager.clear_all_conversations()

     # Return any context needed by tests
     %{conversation_id: "test-conv-123"}
   end
   ```

6. **Assertions**
   - Use specific assertions: `assert result.type == "error"` not `assert result`
   - Test error cases explicitly
   - Verify all fields in complex structures
   - Use pattern matching in assertions when appropriate

---

## Timeline Estimate

**Phase 0: Doctests** (2-3 hours)
- ReqLlmBridge main module: 1 hour
- ErrorHandler: 0.5 hours
- ToolBuilder: 0.5 hours
- ResponseAggregator: 0.5 hours
- ToolExecutor: 0.25 hours
- StreamingAdapter: 0.25 hours

**Phase 1: Unit Tests** (8-10 hours)
- Authentication: 1.5 hours
- ToolExecutor: 1.5 hours
- ToolBuilder: 1.5 hours
- StreamingAdapter: 1 hour
- ConversationManager: 1.5 hours
- ResponseAggregator: 1.5 hours
- ErrorHandler: 1.5 hours
- Main Bridge: 2 hours

**Phase 2: Integration Tests** (2-3 hours)
- Tool conversion flow: 0.5 hours
- Conversation with tools: 0.5 hours
- Response aggregation: 0.5 hours
- Authentication integration: 0.5 hours
- Error flow: 0.5 hours

**Phase 3: Refinement** (2 hours)
- Fix failing tests
- Improve test coverage
- Optimize test performance
- Documentation updates
- Verify all doctests pass

**Total Estimated Time**: 14-18 hours

---

## Next Steps

1. **Review and Approve Plan** ✅
   - Review testing plan with team
   - Confirm scope and approach
   - Approve timeline estimate

2. **Create Test Infrastructure**
   - Set up test helpers
   - Create mock modules if needed
   - Configure test environment
   - Ensure ExUnit is configured to run doctests

3. **Implement Doctests** (Phase 0)
   - Add doctests to module documentation
   - Start with ReqLlmBridge main module
   - Add examples to ErrorHandler, ToolBuilder, ResponseAggregator
   - Verify doctests pass with `mix test --only doctest`

4. **Implement Unit Tests** (Phase 1)
   - Follow module order: Authentication → ToolExecutor → ToolBuilder → StreamingAdapter → ConversationManager → ResponseAggregator → ErrorHandler → Main Bridge
   - Run tests frequently during development
   - Fix issues as they arise

5. **Implement Integration Tests** (Phase 2)
   - Test complete workflows
   - Verify module interactions
   - Ensure system works end-to-end

6. **Verify Success Criteria** (Phase 3)
   - Run full test suite (including doctests)
   - Check all success criteria met
   - Document any deviations

7. **Documentation**
   - Update test documentation
   - Add inline comments for complex tests
   - Create test maintenance guide
   - Ensure all doctests are clear and helpful

---

**Status**: Planning Complete - Ready for Implementation
**Next Action**: Begin implementing doctests starting with ReqLlmBridge main module
