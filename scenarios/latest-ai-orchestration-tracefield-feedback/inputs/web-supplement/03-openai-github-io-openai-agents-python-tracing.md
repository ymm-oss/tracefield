---
kind: web_page
source_url: "https://openai.github.io/openai-agents-python/tracing/"
title: "Tracing - OpenAI Agents SDK"
fetched_at: "2026-06-17T02:11:07.163538+00:00"
content_type: "text/html; charset=utf-8"
bytes: 96444
---

# Tracing - OpenAI Agents SDK

Source: https://openai.github.io/openai-agents-python/tracing/
Fetched: 2026-06-17T02:11:07.163538+00:00

Tracing - OpenAI Agents SDK
Skip to content
OpenAI Agents SDK
Tracing
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
Tracing
Table of contents
Traces and spans
Default tracing
Long-running workers and immediate exports
Higher level traces
Creating traces
Creating spans
Sensitive data
Custom tracing processors
Tracing with non-OpenAI models
Additional notes
Ecosystem integrations
External tracing processors list
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
Traces and spans
Default tracing
Long-running workers and immediate exports
Higher level traces
Creating traces
Creating spans
Sensitive data
Custom tracing processors
Tracing with non-OpenAI models
Additional notes
Ecosystem integrations
External tracing processors list
Tracing
The Agents SDK includes built-in tracing, collecting a comprehensive record of events during an agent run: LLM generations, tool calls, handoffs, guardrails, and even custom events that occur. Using the Traces dashboard , you can debug, visualize, and monitor your workflows during development and in production.
Note
Tracing is enabled by default. You can disable it in three common ways:
You can globally disable tracing by setting the env var OPENAI_AGENTS_DISABLE_TRACING=1
You can globally disable tracing in code with set_tracing_disabled(True)
You can disable tracing for a single run by setting agents.run.RunConfig.tracing_disabled to True
For organizations operating under a Zero Data Retention (ZDR) policy using OpenAI's APIs, tracing is unavailable.
Traces and spans
Traces represent a single end-to-end operation of a "workflow". They're composed of Spans. Traces have the following properties:
workflow_name : This is the logical workflow or app. For example "Code generation" or "Customer service".
trace_id : A unique ID for the trace. Automatically generated if you don't pass one. Must have the format trace_<32_alphanumeric> .
group_id : Optional group ID, to link multiple traces from the same conversation. For example, you might use a chat thread ID.
disabled : If True, the trace will not be recorded.
metadata : Optional metadata for the trace.
Spans represent operations that have a start and end time. Spans have:
started_at and ended_at timestamps.
trace_id , to represent the trace they belong to
parent_id , which points to the parent Span of this Span (if any)
span_data , which is information about the Span. For example, AgentSpanData contains information about the Agent, GenerationSpanData contains information about the LLM generation, etc.
Default tracing
By default, the SDK traces the following:
The entire Runner.{run, run_sync, run_streamed}() is wrapped in a trace() .
Each time an agent runs, it is wrapped in agent_span()
LLM generations are wrapped in generation_span()
Function tool calls are each wrapped in function_span()
Guardrails are wrapped in guardrail_span()
Handoffs are wrapped in handoff_span()
Audio inputs (speech-to-text) are wrapped in a transcription_span()
Audio outputs (text-to-speech) are wrapped in a speech_span()
Related audio spans may be parented under a speech_group_span()
By default, the trace is named "Agent workflow". You can set this name if you use trace , or you can configure the name and other properties with the RunConfig .
In addition, you can set up custom trace processors to push traces to other destinations (as a replacement, or secondary destination).
Long-running workers and immediate exports
The default BatchTraceProcessor exports traces
in the background every few seconds, or sooner when the in-memory queue reaches its size trigger,
and also performs a final flush when the process exits. In long-running workers such as Celery,
RQ, Dramatiq, or FastAPI background tasks, this means traces are usually exported automatically
without any extra code, but they may not appear in the Traces dashboard immediately after each job
finishes.
If you need an immediate delivery guarantee at the end of a unit of work, call
flush_traces() after the trace context exits.
from agents import Runner , flush_traces , trace
@celery_app . task
def run_agent_task ( prompt : str ):
try :
with trace ( "celery_task" ):
result = Runner . run_sync ( agent , prompt )
return result . final_output
finally :
flush_traces ()
from fastapi import BackgroundTasks , FastAPI
from agents import Runner , flush_traces , trace
app = FastAPI ()
def process_in_background ( prompt : str ) -> None :
try :
with trace ( "background_job" ):
Runner . run_sync ( agent , prompt )
finally :
flush_traces ()
@app . post ( "/run" )
async def run ( prompt : str , background_tasks : BackgroundTasks ):
background_tasks . add_task ( process_in_background , prompt )
return { "status" : "queued" }
flush_traces() blocks until currently buffered traces and spans are
exported, so call it after trace() closes to avoid flushing a partially built trace. You can skip
this call when the default export latency is acceptable.
Higher level traces
Sometimes, you might want multiple calls to run() to be part of a single trace. You can do this by wrapping the entire code in a trace() .
from agents import Agent , Runner , trace
async def main ():
agent = Agent ( name = "Joke generator" , instructions = "Tell funny jokes." )
with trace ( "Joke workflow" ): # (1)!
first_result = await Runner . run ( agent , "Tell me a joke" )
second_result = await Runner . run ( agent , f "Rate this joke: { first_result . final_output } " )
print ( f "Joke: { first_result . final_output } " )
print ( f "Rating: { second_result . final_output } " )
Because the two calls to Runner.run are wrapped in a with trace() , the individual runs will be part of the overall trace rather than creating two traces.
Creating traces
You can use the trace() function to create a trace. Traces need to be started and finished. You have two options to do so:
Recommended : use the trace as a context manager, i.e. with trace(...) as my_trace . This will automatically start and end the trace at the right time.
You can also manually call trace.start() and trace.finish() .
The current trace is tracked via a Python contextvar . This means that it works with concurrency automatically. If you manually start/end a trace, you'll need to pass mark_as_current and reset_current to start() / finish() to update the current trace.
Creating spans
You can use the various *_span() methods to create a span. In general, you don't need to manually create spans. A custom_span() function is available for tracking custom span information.
Spans are automatically part of the current trace, and are nested under the nearest current span, which is tracked via a Python contextvar .
Sensitive data
Certain spans may capture potentially sensitive data.
The generation_span() stores the inputs/outputs of the LLM generation, and function_span() stores the inputs/outputs of function calls. These may contain sensitive data, so you can disable capturing that data via RunConfig.trace_include_sensitive_data .
Similarly, Audio spans include base64-encoded PCM data for input and output audio by default. You can disable capturing this audio data by configuring VoicePipelineConfig.trace_include_sensitive_audio_data .
By default, trace_include_sensitive_data is True . You can set the default without code by exporting the OPENAI_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA environment variable to true/1 or false/0 before running your app.
Custom tracing processors
The high level architecture for tracing is:
At initialization, we create a global [ TraceProvider ][agents.tracing.setup.TraceProvider], which is responsible for creating traces.
We configure the TraceProvider with a BatchTraceProcessor that sends traces/spans in batches to a BackendSpanExporter , which exports the spans and traces to the OpenAI backend in batches.
To customize this default setup, to send traces to alternative or additional backends or modifying exporter behavior, you have two options:
add_trace_processor() lets you add an additional trace processor that will receive traces and spans as they are ready. This lets you do your own processing in addition to sending traces to OpenAI's backend.
set_trace_processors() lets you replace the default processors with your own trace processors. This means traces will not be sent to the OpenAI backend unless you include a TracingProcessor that does so.
Tracing with non-OpenAI models
You can use an OpenAI API key with non-OpenAI models to enable free tracing in the OpenAI Traces dashboard without needing to disable tracing. See the Third-party adapters section in the Models guide for adapter selection and setup caveats.
import os
from agents import set_tracing_export_api_key , Agent , Runner
from agents.extensions.models.any_llm_model import AnyLLMModel
tracing_api_key = os . environ [ "OPENAI_API_KEY" ]
set_tracing_export_api_key ( tracing_api_key )
model = AnyLLMModel (
model = "your-provider/your-model-name" ,
api_key = "your-api-key" ,
)
agent = Agent (
name = "Assistant" ,
model = model ,
)
If you only need a different tracing key for a single run, pass it via RunConfig instead of changing the global exporter.
from agents import Runner , RunConfig
await Runner . run (
agent ,
input = "Hello" ,
run_config = RunConfig ( tracing = { "api_key" : "sk-tracing-123" }),
)
Additional notes
View free traces at OpenAI Traces dashboard.
Ecosystem integrations
The following community and vendor integrations support the OpenAI Agents SDK tracing surface.
External tracing processors list
Weights & Biases
Arize-Phoenix
Future AGI
MLflow (self-hosted/OSS)
MLflow (Databricks hosted)
Braintrust
Pydantic Logfire
AgentOps
Scorecard
Respan
LangSmith
Maxim AI
Comet Opik
Langfuse
Langtrace
Okahu-Monocle
Galileo
Portkey AI
LangDB AI
Agenta
PostHog
Traccia
PromptLayer
HoneyHive
Asqav
Datadog
Latitude
