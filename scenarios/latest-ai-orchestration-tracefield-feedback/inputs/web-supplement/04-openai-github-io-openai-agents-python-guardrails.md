---
kind: web_page
source_url: "https://openai.github.io/openai-agents-python/guardrails/"
title: "Guardrails - OpenAI Agents SDK"
fetched_at: "2026-06-17T02:11:07.218203+00:00"
content_type: "text/html; charset=utf-8"
bytes: 103735
---

# Guardrails - OpenAI Agents SDK

Source: https://openai.github.io/openai-agents-python/guardrails/
Fetched: 2026-06-17T02:11:07.218203+00:00

Guardrails - OpenAI Agents SDK
Skip to content
OpenAI Agents SDK
Guardrails
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
Guardrails
Table of contents
Workflow boundaries
Input guardrails
Execution modes
Output guardrails
Tool guardrails
Tripwires
Implementing a guardrail
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
Workflow boundaries
Input guardrails
Execution modes
Output guardrails
Tool guardrails
Tripwires
Implementing a guardrail
Guardrails
Guardrails enable you to do checks and validations of user input and agent output. For example, imagine you have an agent that uses a very smart (and hence slow/expensive) model to help with customer requests. You wouldn't want malicious users to ask the model to help them with their math homework. So, you can run a guardrail with a fast/cheap model. If the guardrail detects malicious usage, it can immediately raise an error and prevent the expensive model from running, saving you time and money ( when using blocking guardrails; for parallel guardrails, the expensive model may have already started running before the guardrail completes. See "Execution modes" below for details ).
There are two kinds of guardrails:
Input guardrails run on the initial user input
Output guardrails run on the final agent output
Workflow boundaries
Guardrails are attached to agents and tools, but they do not all run at the same points in a workflow:
Input guardrails run only for the first agent in the chain.
Output guardrails run only for the agent that produces the final output.
Tool guardrails run on every custom function-tool invocation, with input guardrails before execution and output guardrails after execution.
If you need checks around each custom function-tool call in a workflow that includes managers, handoffs, or delegated specialists, use tool guardrails instead of relying only on agent-level input/output guardrails.
Input guardrails
Input guardrails run in 3 steps:
First, the guardrail receives the same input passed to the agent.
Next, the guardrail function runs to produce a GuardrailFunctionOutput , which is then wrapped in an InputGuardrailResult
Finally, we check if .tripwire_triggered is true. If true, an InputGuardrailTripwireTriggered exception is raised, so you can appropriately respond to the user or handle the exception.
Note
Input guardrails are intended to run on user input, so an agent's guardrails only run if the agent is the first agent. You might wonder, why is the guardrails property on the agent instead of passed to Runner.run ? It's because guardrails tend to be related to the actual Agent - you'd run different guardrails for different agents, so colocating the code is useful for readability.
Execution modes
Input guardrails support two execution modes:
Parallel execution (default, run_in_parallel=True ): The guardrail runs concurrently with the agent's execution. This provides the best latency since both start at the same time. However, if the guardrail fails, the agent may have already consumed tokens and executed tools before being cancelled.
Blocking execution ( run_in_parallel=False ): The guardrail runs and completes before the agent starts. If the guardrail tripwire is triggered, the agent never executes, preventing token consumption and tool execution. This is ideal for cost optimization and when you want to avoid potential side effects from tool calls.
Output guardrails
Output guardrails run in 3 steps:
First, the guardrail receives the output produced by the agent.
Next, the guardrail function runs to produce a GuardrailFunctionOutput , which is then wrapped in an OutputGuardrailResult
Finally, we check if .tripwire_triggered is true. If true, an OutputGuardrailTripwireTriggered exception is raised, so you can appropriately respond to the user or handle the exception.
Note
Output guardrails are intended to run on the final agent output, so an agent's guardrails only run if the agent is the last agent. Similar to the input guardrails, we do this because guardrails tend to be related to the actual Agent - you'd run different guardrails for different agents, so colocating the code is useful for readability.
Output guardrails always run after the agent completes, so they don't support the run_in_parallel parameter.
Tool guardrails
Tool guardrails wrap function tools and let you validate or block tool calls before and after execution. They are configured on the tool itself and run every time that tool is invoked.
Input tool guardrails run before the tool executes and can skip the call, replace the output with a message, or raise a tripwire.
Output tool guardrails run after the tool executes and can replace the output or raise a tripwire.
Tool guardrails apply only to function tools created with function_tool . Handoffs run through the SDK's handoff pipeline rather than the normal function-tool pipeline, so tool guardrails do not apply to the handoff call itself. Hosted tools ( WebSearchTool , FileSearchTool , HostedMCPTool , CodeInterpreterTool , ImageGenerationTool ) and built-in execution tools ( ComputerTool , ShellTool , ApplyPatchTool , LocalShellTool ) also do not use this guardrail pipeline, and Agent.as_tool() does not currently expose tool-guardrail options directly.
See the code snippet below for details.
Tripwires
If the input or output fails the guardrail, the Guardrail can signal this with a tripwire. As soon as we see a guardrail that has triggered the tripwires, we immediately raise a {Input,Output}GuardrailTripwireTriggered exception and halt the Agent execution.
Implementing a guardrail
You need to provide a function that receives input, and returns a GuardrailFunctionOutput . In this example, we'll do this by running an Agent under the hood.
from pydantic import BaseModel
from agents import (
Agent ,
GuardrailFunctionOutput ,
InputGuardrailTripwireTriggered ,
RunContextWrapper ,
Runner ,
TResponseInputItem ,
input_guardrail ,
)
class MathHomeworkOutput ( BaseModel ):
is_math_homework : bool
reasoning : str
guardrail_agent = Agent ( # (1)!
name = "Guardrail check" ,
instructions = "Check if the user is asking you to do their math homework." ,
output_type = MathHomeworkOutput ,
)
@input_guardrail
async def math_guardrail ( # (2)!
ctx : RunContextWrapper [ None ], agent : Agent , input : str | list [ TResponseInputItem ]
) -> GuardrailFunctionOutput :
result = await Runner . run ( guardrail_agent , input , context = ctx . context )
return GuardrailFunctionOutput (
output_info = result . final_output , # (3)!
tripwire_triggered = result . final_output . is_math_homework ,
)
agent = Agent ( # (4)!
name = "Customer support agent" ,
instructions = "You are a customer support agent. You help customers with their questions." ,
input_guardrails = [ math_guardrail ],
)
async def main ():
# This should trip the guardrail
try :
await Runner . run ( agent , "Hello, can you help me solve for x: 2x + 3 = 11?" )
print ( "Guardrail didn't trip - this is unexpected" )
except InputGuardrailTripwireTriggered :
print ( "Math homework guardrail tripped" )
We'll use this agent in our guardrail function.
This is the guardrail function that receives the agent's input/context, and returns the result.
We can include extra information in the guardrail result.
This is the actual agent that defines the workflow.
Output guardrails are similar.
from pydantic import BaseModel
from agents import (
Agent ,
GuardrailFunctionOutput ,
OutputGuardrailTripwireTriggered ,
RunContextWrapper ,
Runner ,
output_guardrail ,
)
class MessageOutput ( BaseModel ): # (1)!
response : str
class MathOutput ( BaseModel ): # (2)!
reasoning : str
is_math : bool
guardrail_agent = Agent (
name = "Guardrail check" ,
instructions = "Check if the output includes any math." ,
output_type = MathOutput ,
)
@output_guardrail
async def math_guardrail ( # (3)!
ctx : RunContextWrapper , agent : Agent , output : MessageOutput
) -> GuardrailFunctionOutput :
result = await Runner . run ( guardrail_agent , output . response , context = ctx . context )
return GuardrailFunctionOutput (
output_info = result . final_output ,
tripwire_triggered = result . final_output . is_math ,
)
agent = Agent ( # (4)!
name = "Customer support agent" ,
instructions = "You are a customer support agent. You help customers with their questions." ,
output_guardrails = [ math_guardrail ],
output_type = MessageOutput ,
)
async def main ():
# This should trip the guardrail
try :
await Runner . run ( agent , "Hello, can you help me solve for x: 2x + 3 = 11?" )
print ( "Guardrail didn't trip - this is unexpected" )
except OutputGuardrailTripwireTriggered :
print ( "Math output guardrail tripped" )
This is the actual agent's output type.
This is the guardrail's output type.
This is the guardrail function that receives the agent's output, and returns the result.
This is the actual agent that defines the workflow.
Lastly, here are examples of tool guardrails.
import json
from agents import (
Agent ,
Runner ,
ToolGuardrailFunctionOutput ,
function_tool ,
tool_input_guardrail ,
tool_output_guardrail ,
)
@tool_input_guardrail
def block_secrets ( data ):
args = json . loads ( data . context . tool_arguments or " {} " )
if "sk-" in json . dumps ( args ):
return ToolGuardrailFunctionOutput . reject_content (
"Remove secrets before calling this tool."
)
return ToolGuardrailFunctionOutput . allow ()
@tool_output_guardrail
def redact_output ( data ):
text = str ( data . output or "" )
if "sk-" in text :
return ToolGuardrailFunctionOutput . reject_content ( "Output contained sensitive data." )
return ToolGuardrailFunctionOutput . allow ()
@function_tool (
tool_input_guardrails = [ block_secrets ],
tool_output_guardrails = [ redact_output ],
)
def classify_text ( text : str ) -> str :
"""Classify text for internal routing."""
return f "length: { len ( text ) } "
agent = Agent ( name = "Classifier" , tools = [ classify_text ])
result = Runner . run_sync ( agent , "hello world" )
print ( result . final_output )
