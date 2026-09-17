# Acme Support Agent — Strands variant

The Acme Support Agent built on the **[Strands Agents SDK](https://strandsagents.com)**,
instrumented with the OpenSearch GenAI SDK. Strands runs the model-driven reasoning
loop; we wrap it in an `invoke_agent` span and the shared tools emit `execute_tool`
spans. Strands also emits OTel spans natively, so its telemetry composes with the
OpenSearch SDK.

By default this variant targets a Bedrock-hosted Claude model (Strands' default
provider), so it uses standard AWS credentials.

> **Verified end to end on Bedrock.** The full nested trace tree is confirmed — the
> OpenSearch SDK's `invoke_agent`/`execute_tool` spans wrap Strands' own native spans
> (`invoke_agent Strands Agents` → `execute_event_loop_cycle` → `chat` → `execute_tool`),
> all with correct `gen_ai.*` attributes.

## Setup

Bring up the stack from [`../acme-support-agent`](../acme-support-agent)
(`docker compose up -d`), then:

```bash
# The GenAI SDK isn't on PyPI yet — install it from source first:
git clone https://github.com/opensearch-project/genai-observability-sdk-py ../genai-observability-sdk-py
pip install -e ../genai-observability-sdk-py

pip install -e ../acme-shared
pip install -e .
export AWS_REGION=us-east-1     # Strands default model is on Bedrock
# (configure AWS credentials via env, profile, or instance role)
```

## Run

```bash
python run.py "where is my order #1007?"
python -m evals.run_evals
```

## What's shared vs. specific

| Shared (from `acme-shared`) | Specific to this variant |
|---|---|
| tools, observability wiring, dataset, golden paths, criteria | the Strands agent builder ([`strands_agent.py`](strands_agent.py)) + eval runner |

Same dataset and golden paths as every other variant, so framework comparisons are
apples-to-apples.
