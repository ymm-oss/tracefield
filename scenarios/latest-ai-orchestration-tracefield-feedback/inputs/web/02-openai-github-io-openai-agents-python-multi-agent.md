---
kind: web_page
source_url: "https://openai.github.io/openai-agents-python/multi_agent/"
title: "Agent orchestration - OpenAI Agents SDK"
fetched_at: "2026-06-16T23:33:20.820861+00:00"
content_type: "text/html; charset=utf-8"
bytes: 68405
---

# Agent orchestration - OpenAI Agents SDK

Source: https://openai.github.io/openai-agents-python/multi_agent/
Fetched: 2026-06-16T23:33:20.820861+00:00

Agent orchestration - OpenAI Agents SDK
Skip to content
OpenAI Agents SDK
Agent orchestration
English
日本語
한국어
简体中文
Initializing search
openai-agents-python
OpenAI Agents SDK
openai-agents-python
Intro
Quickstart
Configuration
Documentation
Documentation
Agents
Sandbox agents
Sandbox agents
Quickstart
Concepts
Sandbox clients
Agent memory
Models
Tools
Guardrails
Running agents
Streaming
Agent orchestration
Agent orchestration
Table of contents
Orchestrating via LLM
Core SDK patterns
Orchestrating via code
Related guides
Handoffs
Results
Human-in-the-loop
Sessions
Sessions
Overview
SQLAlchemy session
Advanced SQLite session
Encrypted session
Context management
Usage
Model context protocol (MCP)
Tracing
Realtime agents
Realtime agents
Quickstart
Transport
Guide
Voice agents
Voice agents
Quickstart
Pipeline
Tracing
Agent visualization
REPL utility
Examples
Release process/changelog
API Reference
API Reference
Agents
Agents
Agents module
Agent
Runner
Run config
Run state
Sandbox
Sandbox
Overview
SandboxAgent
Manifest
Permissions
SnapshotSpec
Workspace entries
Capabilities
Capabilities
Capabilities
Capability
Filesystem
Shell
Memory
Skills
Compaction
Sandbox clients
SandboxSession
SandboxSessionState
Unix local sandbox
Docker sandbox
Responses WebSocket session
Run error handlers
Memory
REPL
Tools
Tool context
Results
Streaming events
Handoffs
Lifecycle
Items
Run context
Usage
Exceptions
Guardrails
Prompts
Model settings
Strict schema
Tool guardrails
Computer
Agent output
Function schema
Model interface
OpenAI Chat Completions model
OpenAI Responses model
OpenAI provider
Multi provider
MCP servers
MCP util
MCP manager
Tracing
Tracing
Tracing module
Creating traces/spans
Traces
Spans
Processor interface
Processors
Scope
Setup
Span data
Util
Realtime
Realtime
RealtimeAgent
RealtimeRunner
RealtimeSession
Events
Configuration
Model
Voice
Voice
Pipeline
Workflow
Input
Result
Pipeline config
Events
Exceptions
Model
Utils
OpenAI voice model provider
OpenAI STT
OpenAI TTS
Extensions
Extensions
Handoff filters
Handoff prompt
Third-party adapters
Third-party adapters
Any-LLM model
Any-LLM provider
LiteLLM model
LiteLLM provider
Tool output trimmer
SQLAlchemySession
Async SQLite session
RedisSession
MongoDBSession
DaprSession
EncryptedSession
AdvancedSQLiteSession
Table of contents
Orchestrating via LLM
Core SDK patterns
Orchestrating via code
Related guides
Agent orchestration
Orchestration refers to the flow of agents in your app. Which agents run, in what order, and how do they decide what happens next? There are two main ways to orchestrate agents:
Allowing the LLM to make decisions: this uses the intelligence of an LLM to plan, reason, and decide on what steps to take based on that.
Orchestrating via code: determining the flow of agents via your code.
You can mix and match these patterns. Each has their own tradeoffs, described below.
Orchestrating via LLM
An agent is an LLM equipped with instructions, tools and handoffs. This means that given an open-ended task, the LLM can autonomously plan how it will tackle the task, using tools to take actions and acquire data, and using handoffs to delegate tasks to sub-agents. For example, a research agent could be equipped with tools like:
Web search to find information online
File search and retrieval to search through proprietary data and connections
Computer use to take actions on a computer
Code execution to do data analysis
Handoffs to specialized agents that are great at planning, report writing and more.
Core SDK patterns
In the Python SDK, two orchestration patterns come up most often:
Pattern
How it works
Best when
Agents as tools
A manager agent keeps control of the conversation and calls specialist agents through Agent.as_tool() .
You want one agent to own the final answer, combine outputs from multiple specialists, or enforce shared guardrails in one place.
Handoffs
A triage agent routes the conversation to a specialist, and that specialist becomes the active agent for the rest of the turn.
You want the specialist to respond directly, keep prompts focused, or swap instructions without the manager narrating the result.
Use agents as tools when a specialist should help with a bounded subtask but should not take over the user-facing conversation. Use handoffs when routing itself is part of the workflow and you want the chosen specialist to own the next part of the interaction.
You can also combine the two. A triage agent might hand off to a specialist, and that specialist can still call other agents as tools for narrow subtasks.
This pattern is great when the task is open-ended and you want to rely on the intelligence of an LLM. The most important tactics here are:
Invest in good prompts. Make it clear what tools are available, how to use them, and what parameters it must operate within.
Monitor your app and iterate on it. See where things go wrong, and iterate on your prompts.
Allow the agent to introspect and improve. For example, run it in a loop, and let it critique itself; or, provide error messages and let it improve.
Have specialized agents that excel in one task, rather than having a general purpose agent that is expected to be good at anything.
Invest in evals . This lets you train your agents to improve and get better at tasks.
If you want the core SDK primitives behind this style of orchestration, start with tools , handoffs , and running agents .
Orchestrating via code
While orchestrating via LLM is powerful, orchestrating via code makes tasks more deterministic and predictable, in terms of speed, cost and performance. Common patterns here are:
Using structured outputs to generate well formed data that you can inspect with your code. For example, you might ask an agent to classify the task into a few categories, and then pick the next agent based on the category.
Chaining multiple agents by transforming the output of one into the input of the next. You can decompose a task like writing a blog post into a series of steps - do research, write an outline, write the blog post, critique it, and then improve it.
Running the agent that performs the task in a while loop with an agent that evaluates and provides feedback, until the evaluator says the output passes certain criteria.
Running multiple agents in parallel, e.g. via Python primitives like asyncio.gather . This is useful for speed when you have multiple tasks that don't depend on each other.
We have a number of examples in examples/agent_patterns .
Related guides
Agents for composition patterns and agent configuration.
Tools for Agent.as_tool() and manager-style orchestration.
Handoffs for delegation between specialist agents.
Running agents for per-run orchestration controls and conversation state.
Quickstart for a minimal end-to-end handoff example.
