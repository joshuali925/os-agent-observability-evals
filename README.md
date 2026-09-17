# OpenSearch AI Agent Observability & Evals

A hands-on tutorial and runnable example for instrumenting, observing, and
**evaluating** AI agents with the [OpenSearch AI observability stack](https://observability.opensearch.org/docs/ai-observability/).

It meets you wherever you are — building a new agent, iterating in dev, or running
one in production — and on whatever framework you already use, then walks the full
journey to a **healthy production agent**:

> **instrument → verify → observe → evaluate → monitor → close the loop**

## What's here

| Path | What it is |
|---|---|
| [`blog.md`](blog.md) | The tutorial walkthrough — read this first |
| [`acme-support-agent/`](acme-support-agent/) | The runnable companion repo: a full example agent + the local stack |

> **Verified against the real SDK + Bedrock.** The instrumentation and agent loops were tested
> end to end with the [OpenSearch GenAI SDK](https://github.com/opensearch-project/genai-observability-sdk-py)
> exporting real OTLP spans, running on Amazon Bedrock (Claude Haiku 4.5). Confirmed: the
> `invoke_agent → chat → execute_tool` trace tree, correct `gen_ai.*` attributes
> (`gen_ai.tool.call.arguments`/`result`, `gen_ai.conversation.id`, `gen_ai.agent.name`), the
> native-SDK eval suite, and the LangChain auto-instrumentor's `chat` spans. See
> [What's tested](#whats-tested).

## The example: Acme Support Agent

One example agent threaded through every step so you can follow it end to end. It's a
customer-support bot for a fictional store, with three deterministic tools
(`lookup_order`, `check_inventory`, `search_policy`) — chosen so evaluation is
**objective** and there's a clear **golden path** for trajectory comparison.

It exercises every span type the stack cares about: `invoke_agent` → `chat` →
`execute_tool` → `retrieval` / `embeddings`. The agent logic and observability code
are written **once**; only the model/tool-calling layer swaps per framework.

## Frameworks covered

The main tutorial ([`acme-support-agent/`](acme-support-agent/)) shows every framework
in one repo:

| Runtime | Frameworks | Path |
|---|---|---|
| **Python** | OpenAI · Anthropic · Bedrock · LangChain · LlamaIndex | native SDK (`opensearch-genai-observability-sdk-py`) |
| **TypeScript** | native SDK [`@opensearch-project/genai-observability-sdk-ts`](https://github.com/opensearch-project/genai-observability-sdk-ts) | `register` + `observe` + `enrich` (parity with Python) |

## Standalone variants

Each variant is a focused, runnable flow for one framework or eval library. They all
share one core ([`acme-shared/`](acme-shared/) — tools, observability, dataset, golden
paths, criteria), so the **only** thing that differs is the agent framework or the eval
layer. That makes them apples-to-apples on the same dataset.

| Variant | Framework | Eval layer |
|---|---|---|
| [`acme-support-agent-py-langgraph`](acme-support-agent-py-langgraph/) | LangGraph | native SDK `score()` |
| [`acme-support-agent-py-strands`](acme-support-agent-py-strands/) | [Strands Agents](https://strandsagents.com) | native SDK `score()` |
| [`acme-support-agent-py-langgraph-deepeval`](acme-support-agent-py-langgraph-deepeval/) | LangGraph | [DeepEval](https://docs.confident-ai.com/) → `score()` |
| [`acme-support-agent-py-langgraph-ragas`](acme-support-agent-py-langgraph-ragas/) | LangGraph | [Ragas](https://docs.ragas.io/) → `score()` |
| [`acme-support-agent-agentcore`](acme-support-agent-agentcore/) | [Bedrock AgentCore Runtime](https://aws.amazon.com/bedrock/agentcore/) | native SDK `score()` |

Every variant emits its eval scores via `score()`, so results land beside the traces in
OpenSearch regardless of which eval library produced them. Each folder has its own
README with setup and run steps.

## Quick start

```bash
# 1. clone
git clone https://github.com/anirudha/os-agent-observability-evals.git
cd os-agent-observability-evals/acme-support-agent

# 2. bring up the stack (OpenSearch, OTel Collector, Data Prepper, Prometheus, Dashboards)
docker compose up -d
./verify/check-stack.sh

# 3. install the SDK from source (it isn't on PyPI yet), then the agent
cd ..
git clone https://github.com/opensearch-project/genai-observability-sdk-py
pip install -e ./genai-observability-sdk-py
cd acme-support-agent/python
pip install -e ".[openai]"          # or [anthropic], [bedrock], [langchain], [llamaindex], [all]
export OPENAI_API_KEY=sk-...
python -m acme.run "where is my order #1007?"

# 4. confirm telemetry landed, then run the eval suite
cd .. && ./verify/check-instrumentation.sh
cd python && python -m evals.run_evals
```

Explore the traces in OpenSearch Dashboards at http://localhost:5601
(`admin` / `My_password_123!@#`).

See [`acme-support-agent/README.md`](acme-support-agent/README.md) for the full
repo layout, per-part mapping, and details.

## The journey

Full index with read / code / run links for every part:
**[`acme-support-agent/docs/README.md`](acme-support-agent/docs/README.md)**.

| Part | Step | In the repo |
|---|---|---|
| 1 | Define goals → eval criteria | [`python/evals/criteria.py`](acme-support-agent/python/evals/criteria.py) |
| 2 | Stand up the stack | [`docker-compose.yml`](acme-support-agent/docker-compose.yml) |
| 3 | Instrument your framework | [`python/acme/observability.py`](acme-support-agent/python/acme/observability.py), [`typescript/src/observability.ts`](acme-support-agent/typescript/src/observability.ts) |
| 4 | Verify telemetry lands | [`verify/`](acme-support-agent/verify/) |
| 5 | Observe & debug | [`verify/queries.md`](acme-support-agent/verify/queries.md) |
| 6 | Evaluate against a dataset | [`python/evals/`](acme-support-agent/python/evals/) |
| 7 | Monitor production | [`infra/prometheus/`](acme-support-agent/infra/prometheus/), [`docs/production.md`](acme-support-agent/docs/production.md) |
| 8 | Close the loop | [`python/evals/dataset.py`](acme-support-agent/python/evals/dataset.py) |

## What's tested

The code was run end to end against the real
[OpenSearch GenAI SDK](https://github.com/opensearch-project/genai-observability-sdk-py)
(installed from source) on **Amazon Bedrock** (Claude Haiku 4.5), with spans exported over
OTLP to a live collector and inspected.

| Area | Status | Notes |
|---|---|---|
| Shared core (`acme-shared`) — tools, observability, dataset, criteria | ✅ tested | imports + run under real `register()` |
| `gen_ai.*` span attributes | ✅ tested | `tool.call.arguments`/`result`, `conversation.id`, `agent.name`, `provider.name`, `request.model` all correct |
| Trace tree `invoke_agent → chat → execute_tool` | ✅ tested | confirmed in collector output |
| LangChain auto-instrumentor `chat` spans | ✅ tested | `ChatBedrockConverse.chat` spans appear automatically |
| **AgentCore** agent loop + eval suite | ✅ tested (Bedrock) | 4/5 eval cases pass; trajectory correct on all 5 |
| **LangGraph** agent + eval suite | ✅ tested (Bedrock) | provider-flexible via `ACME_LLM_PROVIDER` |
| **Original tutorial** Bedrock adapter | ✅ tested (Bedrock) | correct tool calls + answers |
| **Strands** agent | ✅ tested (Bedrock) | full nested trace tree — my spans + Strands' native OTel spans compose |
| **DeepEval** eval suite | ✅ tested end to end (Bedrock) | agent + Bedrock judge (`DEEPEVAL_JUDGE=bedrock`); 4/5; real `gen_ai.evaluation.*` score spans exported |
| **Ragas** eval suite | ✅ tested end to end (Bedrock) | agent + Bedrock judge (`RAGAS_JUDGE=bedrock`); 5/5; pinned versions (see below) |
| **TypeScript** variant | ✅ tested end to end (Bedrock) | native TS SDK v0.1.1; trace tree + auto-captured `gen_ai.tool.call.arguments`/`result` confirmed |

> **Version pins discovered while testing.** `ragas==0.2.14` needs `langchain-core 0.3.x`, which
> conflicts with `langgraph>=1.0` — so the Ragas variant pins `langgraph>=0.2,<0.3`. The Ragas
> 0.4.x line has a broken internal import. DeepEval's Bedrock judge requires `aiobotocore`. All
> of these are encoded in the variants' `pyproject.toml`.

> The recurring "4/5" is the substring answer-judge being strict on the "processing" order, not
> an agent or instrumentation bug — exactly the kind of thing the eval loop surfaces. The golden
> path trajectory is correct on all five cases.

## A note on credentials

The local stack uses default OpenSearch credentials and skips TLS verification —
**local development only.** For the AWS-managed path (Amazon OpenSearch Service +
Amazon Managed Prometheus with SigV4), see
[`acme-support-agent/docs/production.md`](acme-support-agent/docs/production.md).
