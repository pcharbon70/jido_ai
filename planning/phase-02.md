# Phase 2: Extended Provider Support and Legacy Code Removal

## Overview
Building upon the core ReqLLM integration from Phase 1, this phase focuses on expanding Jido AI's capabilities to support all ReqLLM providers, removing legacy provider-specific code, and exposing new model capabilities. We leverage the bridge infrastructure established in Phase 1 to add support for providers that were previously unavailable in Jido AI, while systematically removing the old direct integration code.

This phase transforms Jido AI from supporting 5 core providers to supporting the entire ReqLLM ecosystem (20+ providers), including emerging providers like Groq, Together AI, Replicate, Cohere, and local model support through Ollama. Additionally, we remove technical debt by eliminating provider-specific implementations that are now redundant.

## Prerequisites

- **Phase 1 Complete**: All core ReqLLM infrastructure is in place and tested
- **Existing Tests Passing**: All backward compatibility tests from Phase 1 are green
- **Bridge Layer Stable**: The Jido.AI.ReqLLM module is fully functional
- **Documentation Updated**: Phase 1 migration guide is complete

---

## 2.1 Extended Provider Support
- [ ] **Section 2.1 Complete**

This section adds support for all ReqLLM-supported providers that weren't previously available in Jido AI. Each new provider needs to be integrated, tested, and documented while maintaining the consistent Jido AI interface established in Phase 1.

### 2.1.1 High-Performance Providers
- [ ] **Task 2.1.1 Complete**

High-performance providers like Groq and Together AI offer exceptional speed and throughput. These providers are essential for applications requiring real-time responses or high-volume processing.

- [ ] 2.1.1.1 Add Groq provider support with model mapping and validation
- [ ] 2.1.1.2 Add Together AI provider support with model catalog integration
- [ ] 2.1.1.3 Implement performance benchmarking for new high-speed providers
- [ ] 2.1.1.4 Document latency characteristics and optimization strategies

### 2.1.2 Specialized AI Providers
- [ ] **Task 2.1.2 Complete**

Specialized providers offer unique capabilities like Cohere's RAG-optimized models, Replicate's model marketplace, and Perplexity's search-enhanced AI. These expand Jido AI's capabilities into new domains.

- [ ] 2.1.2.1 Add Cohere provider with command models and RAG features
- [ ] 2.1.2.2 Add Replicate provider with marketplace model support
- [ ] 2.1.2.3 Add Perplexity provider with search-enhanced capabilities
- [ ] 2.1.2.4 Add AI21 Labs provider with Jurassic model family support

### 2.1.3 Local and Self-Hosted Models
- [ ] **Task 2.1.3 Complete**

Local model support through Ollama and LM Studio enables privacy-conscious deployments and offline operation. This is critical for enterprise use cases with data residency requirements.

- [ ] 2.1.3.1 Add Ollama provider for local model execution
- [ ] 2.1.3.2 Add LM Studio provider for desktop model hosting
- [ ] 2.1.3.3 Implement local model discovery and capability detection
- [ ] 2.1.3.4 Add connection validation and health checks for local providers

### 2.1.4 Enterprise and Regional Providers
- [ ] **Task 2.1.4 Complete**

Enterprise providers like Azure OpenAI, Amazon Bedrock, and regional providers expand deployment options for organizations with specific compliance or infrastructure requirements.

- [ ] 2.1.4.1 Add Azure OpenAI provider with tenant-specific configuration
- [ ] 2.1.4.2 Add Amazon Bedrock provider with AWS integration
- [ ] 2.1.4.3 Add Alibaba Cloud provider for China region support
- [ ] 2.1.4.4 Implement provider-specific authentication mechanisms

### Unit Tests - Section 2.1
- [ ] **Unit Tests 2.1 Complete**
- [ ] Test each new provider's model listing and discovery
- [ ] Test provider-specific parameter mapping and validation
- [ ] Test error handling for provider-specific failure modes
- [ ] Test concurrent requests across multiple new providers

---

## 2.2 Model Capability Discovery
- [ ] **Section 2.2 Complete**

This section implements dynamic capability discovery for models across all providers. Instead of hardcoding model capabilities, we query ReqLLM's registry to understand what each model supports (chat, embeddings, vision, function calling, etc.).

### 2.2.1 Capability Detection System
- [ ] **Task 2.2.1 Complete**

The capability detection system automatically discovers and exposes model capabilities through Jido AI's interface, allowing applications to query what operations are supported for any given model.

- [ ] 2.2.1.1 Implement dynamic capability querying from ReqLLM registry
- [ ] 2.2.1.2 Create capability caching system for performance optimization
- [ ] 2.2.1.3 Add capability filtering APIs for model selection
- [ ] 2.2.1.4 Expose capability metadata through Jido.AI.Model struct

### 2.2.2 Multi-Modal Support Detection
- [ ] **Task 2.2.2 Complete**

Multi-modal models support various input and output types beyond text. This system detects and exposes these capabilities, preparing for Phase 3's full multi-modal implementation.

- [ ] 2.2.2.1 Detect vision capabilities (image input support)
- [ ] 2.2.2.2 Detect audio capabilities (speech-to-text, text-to-speech)
- [ ] 2.2.2.3 Detect document processing capabilities (PDF, structured data)
- [ ] 2.2.2.4 Create modality compatibility matrix for providers

### 2.2.3 Cost and Performance Metrics
- [ ] **Task 2.2.3 Complete**

Cost and performance metrics help applications make informed decisions about model selection based on budget and latency requirements.

- [ ] 2.2.3.1 Integrate ReqLLM's pricing information into model metadata
- [ ] 2.2.3.2 Add token cost calculation utilities
- [ ] 2.2.3.3 Expose latency estimates and rate limits
- [ ] 2.2.3.4 Implement cost tracking and budgeting helpers

### Unit Tests - Section 2.2
- [ ] **Unit Tests 2.2 Complete**
- [ ] Test capability detection accuracy across providers
- [ ] Test capability caching and invalidation
- [ ] Test cost calculation accuracy
- [ ] Test modality detection for multi-modal models

---

## 2.3 Legacy Code Removal and Internal Migration
- [ ] **Section 2.3 Complete**

This section systematically migrates internal provider-specific implementations to ReqLLM and removes unused dependencies. This reduces maintenance burden and code complexity while ensuring the public API remains unchanged.

> ⚠️ **Important**: The module names `Jido.AI.Actions.OpenaiEx` and its submodules (`Embeddings`, `ImageGeneration`, `ResponseRetrieve`, `ToolHelper`) are part of the public API and **must be preserved**. Only the internal implementation should be changed to use ReqLLM. Users must be able to continue calling these modules exactly as before.

### 2.3.1 Provider Implementation Migration
- [ ] **Task 2.3.1 Complete**

Migrate provider-specific internal implementations to use ReqLLM while preserving public module names and APIs. The module names like `Jido.AI.Actions.OpenaiEx` must remain unchanged as they are part of the public API documented in guides and used by existing applications.

- [ ] 2.3.1.1 Replace OpenAI API calls inside `Jido.AI.Actions.OpenaiEx` with ReqLLM bridge (preserve module name and public functions)
- [ ] 2.3.1.2 Replace internal Anthropic API calls with ReqLLM while keeping any public interfaces intact
- [ ] 2.3.1.3 Replace internal Google API calls with ReqLLM while keeping any public interfaces intact
- [ ] 2.3.1.4 Replace OpenRouter and Cloudflare internal implementations with ReqLLM calls

### 2.3.2 HTTP Client Code Cleanup
- [ ] **Task 2.3.2 Complete**

Remove custom HTTP client code that was used for provider-specific API calls. ReqLLM handles all HTTP communication internally.

- [ ] 2.3.2.1 Remove provider-specific HTTP header construction
- [ ] 2.3.2.2 Remove custom retry and timeout logic
- [ ] 2.3.2.3 Remove provider-specific response parsing
- [ ] 2.3.2.4 Clean up unused HTTP utility functions

### 2.3.3 Dependency Reduction
- [ ] **Task 2.3.3 Complete**

Remove dependencies that are no longer needed after the ReqLLM migration, reducing the application's dependency footprint while ensuring all public APIs continue to function.

- [ ] 2.3.3.1 Remove OpenaiEx library dependency from mix.exs after confirming all internal calls are migrated to ReqLLM
- [ ] 2.3.3.2 Evaluate and potentially remove provider-specific SDKs that are no longer used internally
- [ ] 2.3.3.3 Update mix.exs to remove unused dependencies while ensuring public module compilation
- [ ] 2.3.3.4 Run dependency audit and cleanup, verify all public APIs still work

### Unit Tests - Section 2.3
- [ ] **Unit Tests 2.3 Complete**
- [ ] Verify all tests still pass after legacy code removal
- [ ] Test that no provider-specific code paths remain active
- [ ] Validate dependency tree has no unused packages
- [ ] Confirm binary size reduction from removed dependencies

---

## 2.4 Provider Adapter Optimization
- [ ] **Section 2.4 Complete**

This section optimizes the provider adapter layer to ensure efficient operation across all providers, implementing provider-specific optimizations where beneficial.

### 2.4.1 Request Optimization
- [ ] **Task 2.4.1 Complete**

Optimize request patterns for each provider to maximize throughput and minimize latency, leveraging ReqLLM's provider-specific optimizations.

- [ ] 2.4.1.1 Implement request batching for providers that support it
- [ ] 2.4.1.2 Add connection pooling optimization per provider
- [ ] 2.4.1.3 Configure optimal timeout values based on provider characteristics
- [ ] 2.4.1.4 Implement adaptive retry strategies per provider

### 2.4.2 Response Processing Optimization
- [ ] **Task 2.4.2 Complete**

Optimize response processing to handle provider-specific response formats efficiently while maintaining the unified Jido AI response structure.

- [ ] 2.4.2.1 Implement streaming response buffering optimization
- [ ] 2.4.2.2 Add response caching for idempotent requests
- [ ] 2.4.2.3 Optimize JSON parsing for large responses
- [ ] 2.4.2.4 Implement response compression where supported

### Unit Tests - Section 2.4
- [ ] **Unit Tests 2.4 Complete**
- [ ] Benchmark request/response performance improvements
- [ ] Test connection pooling effectiveness
- [ ] Validate caching behavior and cache invalidation
- [ ] Test retry strategy effectiveness under failure conditions

---

## 2.5 Advanced Model Features
- [ ] **Section 2.5 Complete**

This section exposes advanced model features that are now accessible through ReqLLM, including features that weren't previously available in Jido AI.

### 2.5.1 Advanced Generation Parameters
- [ ] **Task 2.5.1 Complete**

Expose advanced generation parameters that are supported by modern models but weren't previously accessible through Jido AI.

- [ ] 2.5.1.1 Add support for JSON mode and structured output formats
- [ ] 2.5.1.2 Implement grammar-constrained generation where supported
- [ ] 2.5.1.3 Add support for logit bias and token probability access
- [ ] 2.5.1.4 Expose model-specific fine-tuning parameters

### 2.5.2 Context Window Management
- [ ] **Task 2.5.2 Complete**

Implement intelligent context window management to handle models with varying context sizes, from 4K to 1M+ tokens.

- [ ] 2.5.2.1 Add automatic context window detection per model
- [ ] 2.5.2.2 Implement intelligent context truncation strategies
- [ ] 2.5.2.3 Add support for extended context models (100K+ tokens)
- [ ] 2.5.2.4 Create context window optimization utilities

### 2.5.3 Specialized Model Features
- [ ] **Task 2.5.3 Complete**

Enable access to specialized features offered by specific models or providers that extend beyond basic chat functionality.

- [ ] 2.5.3.1 Add support for retrieval-augmented generation (RAG) models
- [ ] 2.5.3.2 Implement code execution capabilities where supported
- [ ] 2.5.3.3 Add support for model-specific plugins and extensions
- [ ] 2.5.3.4 Enable custom model fine-tuning integration

### Unit Tests - Section 2.5
- [ ] **Unit Tests 2.5 Complete**
- [ ] Test advanced parameter validation and application
- [ ] Test context window management across different models
- [ ] Validate specialized feature availability detection
- [ ] Test graceful degradation when features aren't supported

---

## 2.6 Configuration Management
- [ ] **Section 2.6 Complete**

This section implements comprehensive configuration management for the expanded provider ecosystem, allowing flexible configuration while maintaining simplicity.

### 2.6.1 Provider Configuration System
- [ ] **Task 2.6.1 Complete**

Create a unified configuration system that handles provider-specific settings while maintaining backward compatibility with existing configuration.

- [ ] 2.6.1.1 Design hierarchical configuration structure for providers
- [ ] 2.6.1.2 Implement configuration validation and schema enforcement
- [ ] 2.6.1.3 Add configuration hot-reloading support
- [ ] 2.6.1.4 Create configuration migration from legacy format

### 2.6.2 Environment-Based Configuration
- [ ] **Task 2.6.2 Complete**

Support environment-specific configurations for development, staging, and production deployments with appropriate defaults.

- [ ] 2.6.2.1 Implement environment-aware configuration loading
- [ ] 2.6.2.2 Add support for configuration overlays and overrides
- [ ] 2.6.2.3 Create secure credential management for multiple environments
- [ ] 2.6.2.4 Implement configuration validation for each environment

### Unit Tests - Section 2.6
- [ ] **Unit Tests 2.6 Complete**
- [ ] Test configuration loading and validation
- [ ] Test environment-specific configuration resolution
- [ ] Validate configuration migration from legacy format
- [ ] Test configuration hot-reload functionality

---

## 2.7 Documentation and Migration Guides
- [ ] **Section 2.7 Complete**

This section creates comprehensive documentation for the new providers and features, including migration guides for users adopting the new capabilities.

### 2.7.1 Provider Documentation
- [ ] **Task 2.7.1 Complete**

Document each new provider with examples, best practices, and specific considerations for optimal usage.

- [ ] 2.7.1.1 Create provider comparison matrix with capabilities and costs
- [ ] 2.7.1.2 Write quick-start guides for each new provider
- [ ] 2.7.1.3 Document provider-specific limitations and workarounds
- [ ] 2.7.1.4 Add code examples for common use cases per provider

### 2.7.2 Migration Documentation
- [ ] **Task 2.7.2 Complete**

Create migration guides for users moving from direct provider usage to the ReqLLM-based implementation.

- [ ] 2.7.2.1 Write migration guide from legacy provider code
- [ ] 2.7.2.2 Document configuration migration process
- [ ] 2.7.2.3 Create troubleshooting guide for common migration issues
- [ ] 2.7.2.4 Add performance tuning guide for new providers

### Unit Tests - Section 2.7
- [ ] **Unit Tests 2.7 Complete**
- [ ] Validate all code examples compile and run
- [ ] Test documentation links and references
- [ ] Verify migration scripts work correctly
- [ ] Test quick-start guides end-to-end

---

## 2.8 Integration Tests
- [ ] **Section 2.8 Complete**

Comprehensive integration testing ensures all new providers work correctly and the legacy code removal hasn't broken any functionality.

### 2.8.1 New Provider Testing
- [ ] **Task 2.8.1 Complete**

Test each new provider end-to-end to ensure full functionality through the Jido AI interface.

- [ ] 2.8.1.1 Test all Groq models with various workloads
- [ ] 2.8.1.2 Test Together AI, Cohere, and Replicate providers
- [ ] 2.8.1.3 Test local providers (Ollama, LM Studio) with different models
- [ ] 2.8.1.4 Test enterprise providers (Azure, Bedrock) with auth flows

### 2.8.2 Cross-Provider Compatibility
- [ ] **Task 2.8.2 Complete**

Ensure consistent behavior across all providers for common operations while properly handling provider-specific differences.

- [ ] 2.8.2.1 Test model switching between providers dynamically
- [ ] 2.8.2.2 Validate consistent error handling across providers
- [ ] 2.8.2.3 Test fallback mechanisms when providers are unavailable
- [ ] 2.8.2.4 Verify consistent response formats across all providers

### 2.8.3 Performance Validation
- [ ] **Task 2.8.3 Complete**

Validate that performance meets or exceeds expectations across all providers and that legacy code removal has improved efficiency.

- [ ] 2.8.3.1 Benchmark latency across all providers
- [ ] 2.8.3.2 Test throughput under concurrent load
- [ ] 2.8.3.3 Measure memory usage reduction from legacy code removal
- [ ] 2.8.3.4 Validate startup time improvements

---

## Success Criteria

1. **Provider Coverage**: All ReqLLM providers accessible through Jido AI
2. **Legacy Code Removed**: All provider-specific implementations eliminated
3. **Performance Improved**: 20% reduction in memory usage, faster startup
4. **Feature Parity Plus**: All existing features work plus new capabilities exposed
5. **Documentation Complete**: Every provider documented with examples
6. **Zero Regressions**: All existing tests continue to pass

## Provides Foundation

This phase establishes the infrastructure for:
- Phase 3: Advanced ReqLLM features (multi-modal, advanced streaming)
- Phase 4: Performance optimization and production hardening
- Future: Custom provider additions and specialized integrations

## Key Outputs

- Support for 20+ AI providers through unified interface
- Removal of 5,000+ lines of legacy provider code
- Comprehensive provider documentation and examples
- Performance improvements from optimized architecture
- Extended model capability discovery system