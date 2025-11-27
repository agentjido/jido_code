# Jido Code - Agentic Coding Assistant TUI: Proof-of-Concept Plan

This proof-of-concept plan outlines the implementation of an agentic coding assistant TUI built on the BEAM platform. The system combines Jido's autonomous agent framework with TermUI's Elm Architecture to deliver a fault-tolerant, real-time coding assistant. This plan focuses on establishing the foundational architecture with Chain-of-Thought reasoning, configurable LLM providers, and a minimal but functional TUI interface.

## Overview

The proof-of-concept establishes three core architectural layers: the TUI Presentation Layer using Elm Architecture patterns, the Agent Orchestration Layer built on Jido's GenServer-based agents with Chain-of-Thought reasoning, and a Configuration Layer for LLM provider management. This phase prioritizes demonstrable functionality over feature completeness.

**Key Deliverables**:
- Functional TUI application with Elm Architecture (Model/Update/View)
- LLM Agent using JidoAI with configurable providers (no default - explicit config required)
- Streaming response display showing tokens as they arrive
- Chain-of-Thought reasoning integration for complex queries
- Phoenix PubSub-based communication between TUI and agents
- Configuration system for LLM provider/model selection
- Knowledge graph foundation stub with RDF.ex/libgraph for future expansion

**Proof-of-Concept Scope**: Chat interface with streaming responses, agent interaction with CoT reasoning, configurable LLM backends, proper OTP supervision, and knowledge graph infrastructure placeholder.

## Phase Documents

- [Phase 1: Project Foundation and Core Infrastructure](phase-01.md)
- [Phase 2: LLM Agent with Chain-of-Thought Reasoning](phase-02.md)
- [Phase 3: TUI Application with Elm Architecture](phase-03.md)
- [Phase 4: Integration and Message Flow](phase-04.md)
- [Phase 5: Testing and Documentation](phase-05.md)

## Success Criteria

1. **Functional TUI**: Application starts, displays interface, accepts input, and renders responses
2. **LLM Integration**: Queries are processed by configured LLM provider and responses display correctly
3. **Chain-of-Thought**: Complex queries trigger CoT reasoning with visible step display
4. **Provider Switching**: Runtime model/provider changes work without restart
5. **Fault Tolerance**: Agent crashes recover automatically via supervision
6. **Test Coverage**: Minimum 80% code coverage with passing test suite

## Key Outputs

- Working `jido_code` Elixir application with TUI
- Streaming response display for real-time token output
- Configurable LLM agent supporting Anthropic, OpenAI, OpenRouter (explicit config required)
- Chain-of-Thought reasoning integration for complex queries
- Command interface for runtime configuration
- Knowledge graph infrastructure stub (RDF.ex + libgraph) for future expansion
- Comprehensive test suite and documentation

## Provides Foundation For

- **Phase 2**: Context management and file system integration
- **Phase 3**: Knowledge graph memory implementation
- **Phase 4**: MCP protocol integration for external tools
- **Phase 5**: Multi-agent coordination with specialized skills
