---
kind_label: research_protocol
title: "Research protocol for Ryohin Keikaku investment evaluation"
as_of: "2026-06-18"
---

# Research Protocol

This scenario must be researched by Tracefield. The external operator should not manually choose facts as evidence.

Process:

1. A Codex-backed Tracefield data/search agent discovers candidate URLs.
2. Tracefield web-input fetches the selected URLs into `inputs/web`.
3. Ollama `qwen3.6:27b` webpage/data actors extract source-grounded facts from fetched pages.
4. Codex analysis actors synthesize forecasts, risks, investment evaluation, and artifacts.
5. Any unsupported conclusion must become a recollection question or a caveat.

Financial-safety rule:

The final output is research and evaluation only. It is not personalized investment advice and must not instruct the user to buy or sell.
