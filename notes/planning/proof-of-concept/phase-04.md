# Phase 4: Integration and Message Flow

This phase connects all components into a working system: user input flows to the agent, responses stream back through PubSub, and the TUI updates in real-time. This establishes the core interaction loop.

## 4.1 User Input Processing

User input captured by the TUI must be packaged and sent to the appropriate agent. The flow handles input validation, agent selection, and async dispatch.

### 4.1.1 Input Submission Handler
- [ ] **Task 4.1.1 Complete**

Implement the complete flow from Enter key to agent invocation. Both provider AND model must be configured before allowing chat.

- [ ] 4.1.1.1 In TUI update, handle `:submit` by extracting input_buffer content
- [ ] 4.1.1.2 Check if input is a command (starts with `/`) - route to command handler
- [ ] 4.1.1.3 If not a command, verify both provider and model are configured
- [ ] 4.1.1.4 If unconfigured, show error: "Please configure a model first. Use /model <provider>:<model> or /models <provider> to see options."
- [ ] 4.1.1.5 Clear input_buffer and add user message to messages list
- [ ] 4.1.1.6 Set agent_status to `:processing`
- [ ] 4.1.1.7 Lookup LLMAgent via Registry
- [ ] 4.1.1.8 Classify query for CoT using QueryClassifier
- [ ] 4.1.1.9 Dispatch async task calling appropriate agent function
- [ ] 4.1.1.10 Return updated Model with pending response indicator
- [ ] 4.1.1.11 Write end-to-end test: input → agent → response (success: full round-trip works)

### 4.1.2 Response Streaming
- [ ] **Task 4.1.2 Complete**

Implement token-by-token streaming display showing LLM output as it arrives for better user experience.

- [ ] 4.1.2.1 Configure JidoAI agent with streaming enabled in model options
- [ ] 4.1.2.2 Implement stream handler in LLMAgent that broadcasts chunks via PubSub
- [ ] 4.1.2.3 Agent broadcasts partial responses: `{:stream_chunk, text}` for each token batch
- [ ] 4.1.2.4 TUI update appends chunks to current streaming message with cursor indicator
- [ ] 4.1.2.5 Display streaming indicator (blinking cursor or spinner) during response generation
- [ ] 4.1.2.6 Agent broadcasts completion: `{:stream_end, full_content}` when done
- [ ] 4.1.2.7 TUI finalizes message, removes streaming indicator, clears streaming state
- [ ] 4.1.2.8 Handle stream errors gracefully with error message display
- [ ] 4.1.2.9 Update agent_status to `:idle` on completion
- [ ] 4.1.2.10 Write streaming test verifying incremental display (success: chunks appear progressively)

## 4.2 Configuration Commands

Users can change LLM provider/model at runtime through TUI commands. This enables experimentation without restarting the application.

### 4.2.1 Command Parser
- [ ] **Task 4.2.1 Complete**

Parse and execute configuration commands from user input.

- [ ] 4.2.1.1 Create `JidoCode.Commands` module for command handling
- [ ] 4.2.1.2 Detect command prefix `/` in input
- [ ] 4.2.1.3 Implement `/model <provider>:<model>` command (sets both provider and model)
- [ ] 4.2.1.4 Implement `/model <model>` command (requires provider already set, validates model for current provider)
- [ ] 4.2.1.5 Implement `/provider <provider>` command (sets provider, clears model - user must then select model)
- [ ] 4.2.1.6 Implement `/models` command - opens pick-list modal with models for current provider (error if no provider set), returns selected model
- [ ] 4.2.1.7 Implement `/models <provider>` command - opens pick-list modal with models for specified provider, returns selected model
- [ ] 4.2.1.8 Implement `/providers` command - opens pick-list modal with all available providers, returns selected provider
- [ ] 4.2.1.9 Implement `/config` to display current configuration
- [ ] 4.2.1.10 Implement `/help` listing available commands
- [ ] 4.2.1.11 Return command result or error message for TUI display
- [ ] 4.2.1.12 Write command parsing tests (success: all commands parse correctly)

### 4.2.2 Model Switching
- [ ] **Task 4.2.2 Complete**

Execute model configuration changes and update agent. Any provider from `Jido.AI.Provider.providers/0` is valid. Models are validated against the provider before accepting.

- [ ] 4.2.2.1 On `/model` command, parse provider and model name
- [ ] 4.2.2.2 Validate provider exists in `Jido.AI.Provider.providers/0` (50+ providers supported)
- [ ] 4.2.2.3 Validate model exists for provider via `Jido.AI.Provider.get_model/2`
- [ ] 4.2.2.4 On invalid model, show error: "Model X not found for provider Y. Use /models Y to list available models."
- [ ] 4.2.2.5 Validate API key exists for provider via Keyring
- [ ] 4.2.2.6 Call `LLMAgent.configure/2` with new settings
- [ ] 4.2.2.7 Broadcast `{:config_changed, config}` on success
- [ ] 4.2.2.8 Display success/error message in TUI
- [ ] 4.2.2.9 Write integration test for model switching (success: subsequent queries use new model)

## 4.3 Knowledge Graph Foundation Stub

The knowledge graph stub establishes the RDF.ex and libgraph infrastructure for future context management. This phase creates placeholder modules and basic data structures without implementing full functionality.

### 4.3.1 RDF Infrastructure Setup
- [ ] **Task 4.3.1 Complete**

Create the foundation modules for RDF-based knowledge representation.

- [ ] 4.3.1.1 Create `JidoCode.KnowledgeGraph` namespace module
- [ ] 4.3.1.2 Create `JidoCode.KnowledgeGraph.Store` with basic RDF.Graph wrapper
- [ ] 4.3.1.3 Define placeholder namespace for code entities: `JidoCode.KnowledgeGraph.Vocab.Code`
- [ ] 4.3.1.4 Implement stub functions: `add_entity/2`, `query/2`, `clear/0` returning `:not_implemented`
- [ ] 4.3.1.5 Create `JidoCode.KnowledgeGraph.Entity` struct for code entities (module, function, type)
- [ ] 4.3.1.6 Verify RDF.ex dependency works with basic graph operations (success: can create/query empty graph)

### 4.3.2 Graph Operations Placeholder
- [ ] **Task 4.3.2 Complete**

Create libgraph-based infrastructure for in-memory graph algorithms.

- [ ] 4.3.2.1 Create `JidoCode.KnowledgeGraph.InMemory` module using libgraph
- [ ] 4.3.2.2 Implement stub `build_dependency_graph/1` returning empty graph
- [ ] 4.3.2.3 Implement stub `find_related_entities/2` returning empty list
- [ ] 4.3.2.4 Define graph schema for code relationships (calls, defines, imports)
- [ ] 4.3.2.5 Add placeholder for future GraphRAG integration
- [ ] 4.3.2.6 Write basic test verifying libgraph operations work (success: graph creation/traversal)
