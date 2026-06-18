---
kind: web_page
source_url: "https://learn.microsoft.com/en-us/azure/foundry/concepts/observability"
title: "Observability in Generative AI - Microsoft Foundry | Microsoft Learn"
fetched_at: "2026-06-17T02:11:07.629471+00:00"
content_type: "text/html"
bytes: 59259
---

# Observability in Generative AI - Microsoft Foundry | Microsoft Learn

Source: https://learn.microsoft.com/en-us/azure/foundry/concepts/observability
Fetched: 2026-06-17T02:11:07.629471+00:00

Observability in Generative AI - Microsoft Foundry | Microsoft Learn
Skip to main content
Skip to Ask Learn chat experience
This browser is no longer supported.
Upgrade to Microsoft Edge to take advantage of the latest features, security updates, and technical support.
Download Microsoft Edge
More info about Internet Explorer and Microsoft Edge
Table of contents
Exit editor mode
Ask Learn
Ask Learn
Reading mode
Table of contents
Read in English
Add
Add to plan
Edit
Copy Markdown
Print
Note
Access to this page requires authorization. You can try signing in or changing directories .
Access to this page requires authorization. You can try changing directories .
Observability in generative AI
Feedback
Summarize this article for me
In this article
The AI application lifecycle requires robust evaluation frameworks to ensure AI systems deliver accurate, relevant, and reliable outputs. Without rigorous assessment, AI systems risk generating responses that are inaccurate, inconsistent, poorly grounded, or potentially harmful. Observability enables teams to measure and improve both the quality and safety of AI outputs throughout the development lifecycle—from model selection through production monitoring.
What is observability?
AI observability refers to the ability to monitor, understand, and troubleshoot AI systems throughout their lifecycle. You can trace, evaluate, integrate automated quality gates into CI/CD pipelines, and collect signals such as evaluation metrics, logs, traces, and model outputs to gain visibility into performance, quality, safety, and operational health.
Core observability capabilities
Microsoft Foundry provides three core capabilities that work together to deliver comprehensive observability across the AI application lifecycle:
Evaluation
Evaluators measure the quality, safety, and reliability of AI responses throughout development. Microsoft Foundry provides built-in evaluators including general-purpose quality metrics (coherence, fluency), RAG-specific metrics (groundedness, relevance), safety and security (hate/unfairness, violence, protected materials), and agent-specific metrics (tool call accuracy, task completion), among others. You can also build custom evaluators tailored to your domain-specific requirements.
For a complete list of built-in evaluators, see Built-in evaluators reference .
Monitoring
Production monitoring ensures your deployed AI applications maintain quality and performance in real-world conditions. Integrated with Azure Monitor Application Insights, Microsoft Foundry delivers real-time dashboards tracking operational metrics, token consumption, latency, error rates, and quality scores. You can set up alerts when outputs fail quality thresholds or produce harmful content, enabling rapid issue resolution.
For details on setting up production monitoring, see Monitor agents dashboard .
Tracing
Distributed tracing captures the execution flow of AI applications, providing visibility into LLM calls, tool invocations, agent decisions, and inter-service dependencies. Built on OpenTelemetry standards and integrated with Azure Monitor Application Insights, tracing enables debugging complex agent behaviors, identifying performance bottlenecks, and understanding multi-step reasoning chains. Microsoft Foundry supports tracing for popular frameworks including LangChain, LangGraph, the OpenAI Agents SDK, and the Microsoft Agent Framework.
For guidance on implementing tracing, see Trace agent overview .
What are evaluators?
Evaluators are specialized tools that measure the quality, safety, and reliability of AI responses throughout the development lifecycle.
For a complete list of built-in evaluators, see Built-in evaluators reference .
Evaluators integrate into each stage of the AI lifecycle to ensure reliability, safety, and effectiveness.
The three stages of AI application lifecycle evaluation
Base model selection
Select the right foundation model by comparing quality, task performance, ethical considerations, and safety profiles across different models.
Tools available : Microsoft Foundry benchmark for comparing models on public datasets or your own data, and the Azure AI Evaluation SDK for testing specific model endpoints .
Pre-production evaluation
Before deployment, thorough testing ensures your AI agent or application is production-ready. This stage validates performance through evaluation datasets, identifies edge cases, assesses robustness, and measures key metrics including task adherence, groundedness, relevance, and safety. For building production-ready agents with multi-turn conversations, tool calling, and state management, see Foundry Agent Service .
Evaluation tools and approaches:
Bring your own data : Evaluate AI applications using your own data with quality, safety, or custom evaluators . Use the Foundry portal evaluation wizard or Foundry SDK and view results in the Foundry portal .
AI red teaming agent : The AI red teaming agent simulates complex attacks using Microsoft's PyRIT framework to identify safety and security vulnerabilities before deployment. Best used with human-in-the-loop processes.
Post-production monitoring
After deployment, continuous monitoring ensures your AI application maintains quality in real-world conditions:
Operational metrics : Regular measurement of key AI agent operational metrics
Continuous evaluation : Quality and safety evaluation of production traffic at a sampled rate
Scheduled evaluation : Scheduled quality and safety evaluation using test datasets to detect system drift
Scheduled red teaming : Scheduled adversarial testing to probe for safety and security vulnerabilities
Azure Monitor alerts : Notifications when outputs fail quality thresholds or produce harmful content
Integrated with Azure Monitor Application Insights, the Foundry Observability dashboard delivers real-time insights into performance, safety, and quality metrics, enabling rapid issue resolution and maintaining user trust.
Evaluation quick reference
Purpose
Process
Parameters, guidance, and samples
How to set up tracing?
Configure distributed tracing
Trace overview Trace with Agents SDK
What are you evaluating for?
Identify or build relevant evaluators
Built-in evaluators Custom evaluators Python SDK samples C# SDK samples
What data should you use?
Upload or generate relevant dataset
Select data source
How to run evaluations?
Run evaluation
Agent evaluation runs Remote cloud run
How did my model/AI application perform?
Analyze results
View evaluation results Cluster analysis
How can I improve?
Analyze results and optimize agents
Analyze evaluation failures with cluster analysis . Optimize agents and re-evaluate . Review evaluation results .
Region support, rate limits, and virtual network support
To learn which regions support AI-assisted evaluators, the rate limits that apply to evaluation runs, and how to configure virtual network support for network isolation, see region support, rate limits, and virtual network support for evaluation .
Pricing
Observability features such as risk and safety evaluations and evaluations in the agent playground are billed based on consumption as listed in our Azure pricing page .
Important
Evaluations in the agents playground are enabled by default for all Foundry projects and are included in consumption-based billing. To turn off playground evaluations, select metrics in the upper right of the agents playground and unselect all evaluators.
Related content
Built-in evaluators reference
Virtual network support for evaluation
Foundry control plane
Evaluate generative AI apps by using Foundry
See evaluation results in the Foundry portal
Foundry Transparency Note
Feedback
Was this page helpful?
Yes
No
No
Need help with this topic?
Want to try using Ask Learn to clarify or guide you through this topic?
Ask Learn
Ask Learn
Suggest a fix?
Additional resources
Last updated on
2026-04-03
In this article
Was this page helpful?
Need help with this topic?
Want to try using Ask Learn to clarify or guide you through this topic?
Ask Learn
Ask Learn
Suggest a fix?
en-us
Your Privacy Choices
Theme
Light
Dark
High contrast
AI Disclaimer
Previous Versions
Blog
Contribute
Privacy
Consumer Health Privacy
Terms of Use
Trademarks
&copy; Microsoft 2026
