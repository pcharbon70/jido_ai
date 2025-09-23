# Phase 1: Core ReqLLM Integration Infrastructure

## Overview
This phase establishes the foundational infrastructure to integrate ReqLLM into Jido AI while preserving all existing public APIs and behavior. We follow the research document's migration strategy to replace provider-specific implementations with ReqLLM's unified interface. The goal is to create a seamless transition where existing Jido AI users experience no breaking changes while gaining access to ReqLLM's broader provider and model ecosystem.

The integration maintains Jido AI's philosophy of minimal, opt-in logging and preserves all existing error handling patterns. By the end of this phase, all current Jido AI functionality will be powered by ReqLLM internally, but externally indistinguishable from the current implementation.

---

## 1.1 Prerequisites and Setup
- [x] **Section 1.1 Complete**

This section establishes the basic dependencies and foundational modules needed for ReqLLM integration. We create the bridge layer that will handle translation between Jido AI's current interfaces and ReqLLM's API, ensuring seamless interoperability.

### 1.1.1 Dependency Management
- [x] **Task 1.1.1 Complete**

The first step involves adding ReqLLM as a dependency while ensuring compatibility with existing dependencies. This includes updating the mix.exs file and verifying that ReqLLM doesn't conflict with current dependencies like OpenaiEx, Instructor, and LangChain.

- [x] 1.1.1.1 Add `:req_llm` dependency to mix.exs with appropriate version constraints
- [x] 1.1.1.2 Update dependency versions for compatibility, ensuring no conflicts with existing libs
- [x] 1.1.1.3 Run `mix deps.get` to verify dependency resolution and compilation
- [x] 1.1.1.4 Create initial ReqLLM configuration structure in application config

### 1.1.2 Core Module Architecture
- [x] **Task 1.1.2 Complete**

This subtask creates the primary bridge module that will serve as the translation layer between Jido AI and ReqLLM. The bridge handles message format conversion, error mapping, and ensures that ReqLLM's responses are shaped to match Jido AI's existing contracts.

- [x] 1.1.2.1 Create `Jido.AI.ReqLLM` bridge module with core conversion functions
- [x] 1.1.2.2 Define message conversion helpers for translating between formats
- [x] 1.1.2.3 Implement error mapping utilities to preserve existing error structures
- [x] 1.1.2.4 Add logging integration preservation to maintain opt-in logging behavior

### Unit Tests - Section 1.1
- [x] **Unit Tests 1.1 Complete**
- [x] Test ReqLLM dependency loading and module availability
- [x] Test bridge module compilation and basic function exports
- [x] Test error mapping functions for common error scenarios
- [x] Test logging preservation and configuration handling

---

## 1.2 Model Integration Layer
- [x] **Section 1.2 Complete**

This section focuses on extending the existing `%Jido.AI.Model{}` struct to work with ReqLLM while maintaining full backward compatibility. The key addition is the `reqllm_id` field that maps Jido AI's provider/model combinations to ReqLLM's "provider:model" format.

### 1.2.1 Model Struct Enhancement
- [x] **Task 1.2.1 Complete**

The Model struct needs to be enhanced with ReqLLM-specific information while preserving all existing fields and behavior. The `reqllm_id` field will be computed automatically when models are created through `Jido.AI.Model.from/1`.

- [x] 1.2.1.1 Add `reqllm_id :: String.t()` field to `%Jido.AI.Model{}` struct definition
- [x] 1.2.1.2 Implement ReqLLM ID computation logic (e.g., "openai:gpt-4o" from {:openai, model: "gpt-4o"})
- [x] 1.2.1.3 Update `Jido.AI.Model.from/1` to automatically populate `reqllm_id` field
- [x] 1.2.1.4 Maintain backward compatibility for all existing model fields and behaviors

### 1.2.2 Provider Mapping
- [x] **Task 1.2.2 Complete**

This creates the mapping logic between Jido AI's current provider system and ReqLLM's provider addressing scheme. It handles model name normalization and provides fallbacks for edge cases.

- [x] 1.2.2.1 Create provider-to-ReqLLM mapping configuration with all supported providers
- [x] 1.2.2.2 Handle model name normalization for ReqLLM format requirements
- [x] 1.2.2.3 Implement fallback mechanisms for unsupported or deprecated models
- [x] 1.2.2.4 Add validation to ensure ReqLLM model availability before requests

### Unit Tests - Section 1.2
- [x] **Unit Tests 1.2 Complete**
- [x] Test model struct creation with automatically computed reqllm_id
- [x] Test provider mapping accuracy across all supported providers
- [x] Test model name normalization for various input formats
- [x] Test backward compatibility preservation for existing model creation patterns

---

## 1.3 Core Action Migration
- [ ] **Section 1.3 Complete**

This section represents the heart of the migration, replacing the current provider-specific implementations in actions like `Jido.AI.Actions.OpenaiEx` with ReqLLM calls. The critical requirement is preserving exact response shapes and error formats that existing Jido AI consumers depend on.

### 1.3.1 Chat/Completion Actions
- [x] **Task 1.3.1 Complete**

The primary chat completion functionality needs to be migrated from OpenaiEx and provider-specific implementations to ReqLLM's unified `generate_text/3` function. This requires careful message format conversion and response shape preservation.

- [x] 1.3.1.1 Replace `OpenaiEx.Chat.Completions.create` calls with `ReqLLM.generate_text/3`
- [x] 1.3.1.2 Implement message format conversion from Jido's message format to ReqLLM's expected format
- [x] 1.3.1.3 Preserve existing response structure and contracts that downstream consumers expect
- [x] 1.3.1.4 Handle provider-specific parameter mapping and validation through ReqLLM

### 1.3.2 Streaming Support
- [x] **Task 1.3.2 Complete**

Streaming functionality is critical for real-time applications. The migration must preserve the exact streaming chunk format and timing that existing consumers rely on, while leveraging ReqLLM's streaming capabilities.

- [x] 1.3.2.1 Replace current streaming implementations with `ReqLLM.stream_text/3`
- [x] 1.3.2.2 Maintain existing stream chunk contracts and shapes for backward compatibility
- [x] 1.3.2.3 Implement stream adapter layer to transform ReqLLM chunks to Jido format
- [x] 1.3.2.4 Preserve error handling and recovery mechanisms in streaming context

### 1.3.3 Embeddings Integration
- [x] **Task 1.3.3 Complete**

Embeddings support needs to be migrated to ReqLLM while maintaining the existing result structure and metadata that applications depend on for vector operations.

- [x] 1.3.3.1 Replace current embedding actions with `ReqLLM.embed_many/3` calls
- [x] 1.3.3.2 Maintain existing embedding result structure including dimensions and metadata
- [x] 1.3.3.3 Handle dimension validation and preserve embedding metadata for compatibility
- [x] 1.3.3.4 Implement batch processing compatibility for large embedding operations

### Unit Tests - Section 1.3
- [ ] **Unit Tests 1.3 Complete**
- [ ] Test chat completion response format preservation across all providers
- [ ] Test streaming chunk structure compatibility and timing behavior
- [ ] Test embedding result structure maintenance and metadata preservation
- [ ] Test error response format consistency with existing implementations

---

## 1.4 Tool/Function Calling Integration
- [ ] **Section 1.4 Complete**

Tool calling is a complex feature that requires careful integration with ReqLLM's tool system while preserving Jido AI's existing Action-based tool framework. This section ensures that existing Jido Actions can be seamlessly used as ReqLLM tools.

### 1.4.1 Tool Descriptor Creation
- [ ] **Task 1.4.1 Complete**

This creates the bridge between Jido's Action system and ReqLLM's tool descriptor format, ensuring that existing Jido Actions can be automatically converted to ReqLLM-compatible tools.

- [ ] 1.4.1.1 Implement conversion from Jido Action modules to ReqLLM tool descriptor format
- [ ] 1.4.1.2 Create callback system for tool execution that invokes Jido Actions properly
- [ ] 1.4.1.3 Ensure all tool return values are JSON-serializable as required by ReqLLM
- [ ] 1.4.1.4 Preserve existing tool response aggregation and result formatting

### 1.4.2 Tool Execution Pipeline
- [ ] **Task 1.4.2 Complete**

The tool execution pipeline needs to integrate ReqLLM's tool calling with Jido's existing tool flow, maintaining the same execution semantics and error handling.

- [ ] 1.4.2.1 Integrate ReqLLM tool calling mechanism with existing Jido tool execution flow
- [ ] 1.4.2.2 Maintain `tool_response` structure compatibility for existing consumers
- [ ] 1.4.2.3 Handle tool choice parameter mapping between Jido and ReqLLM formats
- [ ] 1.4.2.4 Preserve tool error handling, validation, and timeout behaviors

### Unit Tests - Section 1.4
- [ ] **Unit Tests 1.4 Complete**
- [ ] Test tool descriptor generation from various Jido Action module types
- [ ] Test tool execution callback mechanism and parameter passing
- [ ] Test tool response structure preservation and formatting
- [ ] Test tool error handling compatibility and error propagation

---

## 1.5 Key Management Bridge
- [ ] **Section 1.5 Complete**

This section creates the bridge between Jido AI's existing key management system (Jido.AI.Keyring) and ReqLLM's key storage and precedence system. The goal is to maintain the exact same key management behavior from the user's perspective.

### 1.5.1 Keyring Integration
- [ ] **Task 1.5.1 Complete**

The keyring integration ensures that existing key management workflows continue to work while leveraging ReqLLM's key storage capabilities internally.

- [ ] 1.5.1.1 Map Jido.AI.Keyring helper functions to ReqLLM key store operations
- [ ] 1.5.1.2 Implement key precedence delegation (ENV vars → app config → in-memory keys)
- [ ] 1.5.1.3 Preserve existing key management API surface for backward compatibility
- [ ] 1.5.1.4 Handle per-request key overrides and session-based key management

### 1.5.2 Authentication Flow
- [ ] **Task 1.5.2 Complete**

The authentication flow needs to bridge between Jido's current authentication mechanisms and ReqLLM's authentication system while preserving existing validation behavior.

- [ ] 1.5.2.1 Bridge authentication mechanisms between Jido and ReqLLM systems
- [ ] 1.5.2.2 Maintain existing API key validation behavior and error messages
- [ ] 1.5.2.3 Preserve session-based key management and per-user key isolation
- [ ] 1.5.2.4 Handle provider-specific authentication requirements through ReqLLM

### Unit Tests - Section 1.5
- [ ] **Unit Tests 1.5 Complete**
- [ ] Test key precedence order preservation across different key sources
- [ ] Test API key validation compatibility and error message consistency
- [ ] Test per-request override functionality and session isolation
- [ ] Test session key management behavior and lifecycle

---

## 1.6 Provider Discovery and Listing
- [ ] **Section 1.6 Complete**

This section migrates Jido AI's provider and model discovery mechanisms to use ReqLLM's registry while maintaining the existing APIs that applications use for provider enumeration and model listing.

### 1.6.1 Provider Registry Migration
- [ ] **Task 1.6.1 Complete**

The provider registry migration replaces Jido's custom provider listing with ReqLLM's provider registry while maintaining the same external API surface.

- [ ] 1.6.1.1 Replace custom provider listing logic with ReqLLM registry queries
- [ ] 1.6.1.2 Maintain existing provider enumeration APIs and response formats
- [ ] 1.6.1.3 Preserve provider metadata and capability information for applications
- [ ] 1.6.1.4 Handle provider-specific configuration bridging and validation

### 1.6.2 Model Catalog Integration
- [ ] **Task 1.6.2 Complete**

Model catalog integration provides access to ReqLLM's broader model ecosystem while preserving Jido's existing model discovery and filtering capabilities.

- [ ] 1.6.2.1 Migrate model discovery mechanisms to ReqLLM's model registry
- [ ] 1.6.2.2 Preserve existing model listing and filtering APIs for applications
- [ ] 1.6.2.3 Maintain model metadata structure compatibility and information richness
- [ ] 1.6.2.4 Handle model availability checking and capability mapping

### Unit Tests - Section 1.6
- [ ] **Unit Tests 1.6 Complete**
- [ ] Test provider listing API preservation and response format consistency
- [ ] Test model discovery functionality and metadata completeness
- [ ] Test metadata structure compatibility across different providers
- [ ] Test filtering and search capabilities for models and providers

---

## 1.7 Error Handling and Logging
- [ ] **Section 1.7 Complete**

This section ensures that ReqLLM's error handling and logging behavior is mapped to match Jido AI's existing patterns. This is critical for maintaining application stability and debugging capabilities.

### 1.7.1 Error Mapping Layer
- [ ] **Task 1.7.1 Complete**

The error mapping layer translates ReqLLM's error formats to Jido's existing error structures, ensuring that error handling code in applications continues to work unchanged.

- [ ] 1.7.1.1 Map ReqLLM error types and structures to existing Jido error formats
- [ ] 1.7.1.2 Preserve `{:ok, result}` / `{:error, reason}` patterns across all functions
- [ ] 1.7.1.3 Maintain existing error categorization and detailed error information
- [ ] 1.7.1.4 Handle timeout, retry, and network error mapping consistently

### 1.7.2 Logging Preservation
- [ ] **Task 1.7.2 Complete**

Logging preservation ensures that Jido AI's deliberately minimal and opt-in logging behavior is maintained, with ReqLLM's internal logging appropriately managed.

- [ ] 1.7.2.1 Maintain existing opt-in logging behavior with no new default logging
- [ ] 1.7.2.2 Preserve log levels, message formats, and logging configuration options
- [ ] 1.7.2.3 Map ReqLLM internal logs appropriately without creating log noise
- [ ] 1.7.2.4 Document ReqLLM debug/trace options for advanced troubleshooting

### Unit Tests - Section 1.7
- [ ] **Unit Tests 1.7 Complete**
- [ ] Test error structure preservation across different error scenarios
- [ ] Test logging behavior consistency and configuration handling
- [ ] Test error categorization accuracy and information preservation
- [ ] Test timeout/retry error handling and recovery mechanisms

---

## 1.8 Integration Tests
- [ ] **Section 1.8 Complete**

This section provides comprehensive end-to-end testing to validate that the ReqLLM integration works correctly across all supported providers and maintains full backward compatibility.

### 1.8.1 End-to-End Provider Testing
- [ ] **Task 1.8.1 Complete**

End-to-end provider testing validates that each currently supported provider works correctly through the ReqLLM integration, maintaining the same behavior and capabilities.

- [ ] 1.8.1.1 Test OpenAI provider functionality through ReqLLM integration layer
- [ ] 1.8.1.2 Test Anthropic provider functionality through ReqLLM integration layer
- [ ] 1.8.1.3 Test Google provider functionality through ReqLLM integration layer
- [ ] 1.8.1.4 Test OpenRouter provider functionality through ReqLLM integration layer
- [ ] 1.8.1.5 Test Cloudflare provider functionality through ReqLLM integration layer

### 1.8.2 Backward Compatibility Validation
- [ ] **Task 1.8.2 Complete**

Backward compatibility validation ensures that existing applications and test suites continue to work without modification after the ReqLLM integration.

- [ ] 1.8.2.1 Run complete existing test suite against ReqLLM-powered implementation
- [ ] 1.8.2.2 Verify response shape preservation across all actions and providers
- [ ] 1.8.2.3 Test streaming compatibility with existing consumer applications
- [ ] 1.8.2.4 Validate tool calling flow preservation and execution semantics

### 1.8.3 Performance and Behavior Parity
- [ ] **Task 1.8.3 Complete**

Performance and behavior parity testing ensures that the ReqLLM integration doesn't introduce performance regressions or behavioral changes.

- [ ] 1.8.3.1 Benchmark ReqLLM implementation against current direct implementation
- [ ] 1.8.3.2 Test concurrent request handling and connection management
- [ ] 1.8.3.3 Verify timeout and retry behavior consistency with current implementation
- [ ] 1.8.3.4 Test memory usage patterns and resource management efficiency

---

## Success Criteria

1. **API Preservation**: All existing public APIs work unchanged with identical signatures
2. **Response Compatibility**: All response shapes and error formats preserved exactly
3. **Provider Coverage**: All current providers functional through ReqLLM with same capabilities
4. **Extended Access**: New ReqLLM-supported models accessible via existing Jido AI APIs
5. **Performance Parity**: No significant performance degradation in throughput or latency
6. **Test Suite**: 100% existing test suite passes with ReqLLM backend

## Provides Foundation

This phase establishes the infrastructure for:
- Phase 2: Extended provider and model support from ReqLLM ecosystem
- Phase 3: Advanced ReqLLM features integration (advanced streaming, multimodal)
- Phase 4: Performance optimization and technical debt cleanup

## Key Outputs

- Fully functional ReqLLM integration with preserved public APIs
- Comprehensive bridge modules for seamless compatibility
- Extended model and provider coverage beyond current limitations
- Complete test coverage for integration layer and compatibility validation
- Documentation for ReqLLM configuration and troubleshooting