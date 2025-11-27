# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains design and research documentation for an **Agentic Coding Assistant TUI** built in Elixir. The system combines:

- **Jido** - Autonomous agent framework for BEAM
- **TermUI** - Elm Architecture TUI framework
- **Knowledge Graph Memory** - RDF-backed persistent context for LLM interactions
- **MCP/A2A Protocols** - External tool and agent integration

The project is currently in the research/architecture phase with no implementation code yet.

## Architecture Layers

1. **TUI Layer** - Elm Architecture (Model → Update → View) with Phoenix PubSub for agent events
2. **Agent Layer** - Specialized Jido agents (Coordinator, Context, CodeAnalyzer, LLM) communicating via CloudEvents signals
3. **Protocol Layer** - MCP client (Anubis), Phoenix Channels, A2A gateway, filesystem sensors

## Key Design Patterns

- **Jido Skills** - Encapsulate domain capabilities with signal routing, state, and child process supervision
- **Jido Actions** - Validated, schema-driven operations that convert directly to LLM tool definitions
- **Interrupt Priority Queue** - Manages agent notifications to TUI (critical/high/medium/low)
- **GraphRAG** - Hybrid retrieval combining vector search, graph traversal, and community summaries

## Knowledge Graph Design

Uses RDF-based storage:
- **RDF.ex** for semantic linking and OWL reasoning
- **libgraph** for in-memory algorithm operations

Code entities extend CodeOntology with Elixir-specific constructs: modules, pattern-matched functions, OTP behaviours, supervision trees, protocols, macros, TypeSpecs.

## Planned Dependencies

```elixir
# Agent framework
{:jido, "~> 1.0"}
{:jido_ai, "~> 1.0"}

# TUI
{:term_ui, "~> 0.1"}

# Knowledge Graph
{:rdf, "~> 2.0"}
{:sparql, "~> 0.3"}
{:libgraph, "~> 0.16"}

# MCP
{:anubis_mcp, "~> 0.1"}

# Phoenix PubSub
{:phoenix_pubsub, "~> 2.1"}
```

## Research Documents

- `notes/research/1.00-architecture/` - Core multi-agent TUI architecture design
- `notes/research/1.01-knowledge-base/` - Knowledge graph memory design and ontology research
