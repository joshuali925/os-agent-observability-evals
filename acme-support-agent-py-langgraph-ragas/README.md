# Acme Support Agent — LangGraph + Ragas

Same LangGraph agent as [`../acme-support-agent-py-langgraph`](../acme-support-agent-py-langgraph),
evaluated with **[Ragas](https://docs.ragas.io/)**. Ragas' scores are emitted via
`score()` so they land beside the traces in OpenSearch.

## Metrics

| Ragas metric | What it checks |
|---|---|
| `AspectCritic("correctness")` | LLM-judged: is the answer correct vs. the expected fact? |
| tool-call accuracy | did the agent call the expected tool, on the golden path? |

## Setup

Bring up the stack from [`../acme-support-agent`](../acme-support-agent)
(`docker compose up -d`), then:

```bash
# The GenAI SDK isn't on PyPI yet — install it from source first:
git clone https://github.com/opensearch-project/genai-observability-sdk-py ../genai-observability-sdk-py
pip install -e ../genai-observability-sdk-py

pip install -e ../acme-shared
pip install -e .
export OPENAI_API_KEY=sk-...     # used by the agent and the Ragas judge
```

> **Version note:** this variant pins `ragas==0.2.14`, `langchain-community==0.3.14`, and
> `langgraph>=0.2,<0.3` — ragas 0.2.x needs `langchain-core 0.3.x`, which is incompatible with
> `langgraph>=1.0`. These pins are verified working end to end (5/5 on Bedrock).

### Run everything on Bedrock (no OpenAI key)

The agent and the Ragas judge can both run on Amazon Bedrock — verified end to end (5/5):

```bash
pip install -e ".[bedrock]"             # adds langchain-aws
export ACME_LLM_PROVIDER=bedrock        # agent on Bedrock
export RAGAS_JUDGE=bedrock              # Ragas AspectCritic judge on Bedrock
export AWS_REGION=us-east-1             # plus AWS credentials
# judge model override: RAGAS_JUDGE_MODEL=...
```

## Run

```bash
python run.py "where is my order #1007?"
python -m evals.run_evals
```

## Why two eval-library variants?

[`-deepeval`](../acme-support-agent-py-langgraph-deepeval) and `-ragas` run the
**identical agent and dataset** through different eval libraries. Comparing them shows
how each library frames correctness and tool-use — and that, either way, the scores
end up next to your traces in OpenSearch via `score()`.
