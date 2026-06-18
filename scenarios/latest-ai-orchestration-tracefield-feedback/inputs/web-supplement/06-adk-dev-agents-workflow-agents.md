---
kind: web_page
source_url: "https://adk.dev/agents/workflow-agents/"
title: "Template agent workflows - Agent Development Kit (ADK)"
fetched_at: "2026-06-17T02:11:07.439738+00:00"
content_type: "text/html; charset=utf-8"
bytes: 108524
---

# Template agent workflows - Agent Development Kit (ADK)

Source: https://adk.dev/agents/workflow-agents/
Fetched: 2026-06-17T02:11:07.439738+00:00

Template agent workflows - Agent Development Kit (ADK)
Agent Development Kit (ADK)
Skip to content
ADK Python 2.0 GA
is LIVE with graph workflows and collaborative agents, and check out
ADK Kotlin !
Agent Development Kit (ADK)
Template agent workflows
Python
JS
Go
Java
Kotlin
Initializing search
Home
Build Agents
Run Agents
Components
Integrations
Reference
Community
ADK 2.0
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
--
Python
JS
Go
Java
Kotlin
Home
Build Agents
Build Agents
Get Started
Get Started
Python
TypeScript
Go
Java
Kotlin
Installation
Build your Agent
Build your Agent
Multi-tool agent
Agent team
Streaming agent
Streaming agent
Python
Java
Code with AI
Agent Config
Agents
Agents
Simple agents
Graph Workflows
Graph Workflows
Graph routes
Data handling
Human input
Dynamic workflows
Multi-Agent Workflows
Multi-Agent Workflows
Collaborative workflows
Template workflows
Template workflows
Sequential workflow
Loop workflow
Parallel workflow
Custom template workflows
Agent routing
Workflow patterns
Models for Agents
Models for Agents
Gemini
Gemma
Claude
Agent Platform hosted
Apigee AI Gateway
Model routing
Ollama
vLLM
LiteLLM
LiteRT-LM
Run Agents
Run Agents
Agent Runtime
Agent Runtime
Web Interface
Web Interface
Visual Builder
Command Line
API Server
Ambient Agents
Resume Agents
Cancel Agent Runs
Runtime Config
Event Loop
Deployment
Deployment
Agent Runtime
Agent Runtime
Standard deployment
agents-cli
Test deployed agents
Cloud Run
GKE
Observability
Observability
Logging
Metrics
Traces
Evaluation
Evaluation
Criteria
User Simulation
Environment Simulation
Custom Metrics
Optimization
Safety and Security
Safety and Security
Components
Components
Technical Overview
Custom Tools
Custom Tools
Function tools
Function tools
Overview
Tool performance
Action confirmations
MCP tools
OpenAPI tools
Authentication
Tool limitations
Artifacts
Artifacts
Skills for Agents
Skills for Agents
App management
App management
Callbacks
Callbacks
Types of callbacks
Callback patterns
Plugins
Context
Context
Context caching
Context compression
Sessions and Memory
Sessions and Memory
Sessions
Sessions
Rewind sessions
Migrate sessions
State
Events
Memory
MCP
MCP
A2A Protocol
A2A Protocol
Introduction to A2A
A2A Quickstart (Exposing)
A2A Quickstart (Exposing)
Python
Go
Java
A2A Quickstart (Consuming)
A2A Quickstart (Consuming)
Python
Go
Java
A2A Extension
Gemini Live API Toolkit
Gemini Live API Toolkit
Gemini Live API Toolkit development guide series
Gemini Live API Toolkit development guide series
Part 1. Intro to streaming
Part 2. Sending messages
Part 3. Event handling
Part 4. Run configuration
Part 5. Audio, Images, and Video
Streaming Tools
Configuring streaming behavior
Grounding
Grounding
Google Search Grounding
Grounding with Search
Integrations
Integrations
Reference
Reference
API Reference
API Reference
Python ADK
Typescript ADK
Go ADK
Java ADK
Kotlin ADK
CLI Reference
Agent Config Reference
REST API
Release Notes
Community
Community
Contributing Guide
ADK 2.0
ADK 2.0
Home
Build Agents
Multi-Agent Workflows
Template workflows
Template agent workflows &para;
Supported in ADK Python v0.1.0 Typescript v0.2.0 Go v0.1.0 Java v0.1.0
This section introduces template workflows , also known as workflow agents ,
which are specialized agents that control the execution flow of one or more
sub-agents. Template workflow agents are specialized components designed for
orchestrating the execution flow of sub-agents. Their primary role is to manage
how and when other agents run, defining the control flow of a process.
Alternative: graph-based workflows
Starting in ADK 2.0, template workflows have been superseded
by more flexible workflow structures, including
graph-based workflows and
dynamic workflows .
These workflow architectures provide more control, flexibility
and capability to evolve your agent workflows over time.
Figure 1. Execution patterns of template workflows in ADK
Template workflow agents operate based on predefined logic. They determine the
execution sequence according to their type, such as sequential, parallel, or
loop, without consulting an AI model for assistance with the orchestration. This
approach results in deterministic and predictable execution patterns. Template
workflows include the following task execution structures, which each implement
a distinct task completion pattern:
Sequential Agent workflow
Executes sub-agents one after another, in sequence.
Learn more
Loop Agent workflow
Repeatedly executes its sub-agents until a specific termination condition is met.
Learn more
Parallel Agent workflow
Executes multiple sub-agents in parallel.
Learn more
Back to top
Copyright Google 2026 | License | Privacy | Manage cookies
Made with
Material for MkDocs
Cookie consent
We use cookies to recognize repeated visits and preferences, as well as to measure the effectiveness of our documentation and whether users find the information they need. With your consent, you're helping us to make our documentation better.
Google Analytics
GitHub
Accept
Manage settings
