# Acme Support Agent — LangGraph variant

The Acme Support Agent built on **LangGraph** (prebuilt ReAct agent), instrumented
with the OpenSearch GenAI SDK, evaluated with the SDK's **native** scoring.

This is the baseline LangGraph flavor. Two siblings swap the judging layer for an
external eval library while reusing the same agent, dataset, and golden paths:

- [`../acme-support-agent-py-langgraph-deepeval`](../acme-support-agent-py-langgraph-deepeval) — DeepEval
- [`../acme-support-agent-py-langgraph-ragas`](../acme-support-agent-py-langgraph-ragas) — Ragas

## Setup

Bring up the stack from the original tutorial folder
([`../acme-support-agent`](../acme-support-agent)) — `docker compose up -d` — then:

```bash
# The GenAI SDK isn't on PyPI yet — install it from source first:
git clone https://github.com/opensearch-project/genai-observability-sdk-py ../genai-observability-sdk-py
pip install -e ../genai-observability-sdk-py

pip install -e ../acme-shared      # shared tools, observability, dataset, criteria
pip install -e .                   # this variant
export OPENAI_API_KEY=sk-...
```

### Run on Bedrock instead of OpenAI

The agent is provider-flexible. To run against Amazon Bedrock:

```bash
pip install -e ".[bedrock]"        # adds langchain-aws
export ACME_LLM_PROVIDER=bedrock
export AWS_REGION=us-east-1         # plus AWS credentials (env/profile/role)
# default model: global.anthropic.claude-haiku-4-5-20251001-v1:0
# override with ACME_MODEL=...
```

## Run

```bash
python run.py "where is my order #1007?"
python -m evals.run_evals
```

## What's shared vs. specific

| Shared (from `acme-shared`) | Specific to this variant |
|---|---|
| tools, observability wiring, dataset, golden paths, criteria | the LangGraph agent builder + native-SDK eval runner |

The agent itself lives in [`acme_shared/langgraph_agent.py`](../acme-shared/acme_shared/langgraph_agent.py)
since three variants share it.
