# Acme Support Agent — LangGraph + DeepEval

Same LangGraph agent as [`../acme-support-agent-py-langgraph`](../acme-support-agent-py-langgraph),
but the evaluation layer is **[DeepEval](https://docs.confident-ai.com/)** instead of
the native scorer.

The point: you can keep your preferred eval library and *still* have its scores land
beside your traces. The runner emits DeepEval's results via `score()`, so
`deepeval.answer_relevancy` and `deepeval.tool_correctness` show up on the same traces
in OpenSearch — no separate silo.

## Metrics

| DeepEval metric | What it checks |
|---|---|
| `AnswerRelevancyMetric` | LLM-as-judge: is the answer relevant and correct? |
| `ToolCorrectnessMetric` | did the agent call the expected tool(s)? |

## Setup

Bring up the stack from [`../acme-support-agent`](../acme-support-agent)
(`docker compose up -d`), then:

```bash
# The GenAI SDK isn't on PyPI yet — install it from source first:
git clone https://github.com/opensearch-project/genai-observability-sdk-py ../genai-observability-sdk-py
pip install -e ../genai-observability-sdk-py

pip install -e ../acme-shared
pip install -e .
export OPENAI_API_KEY=sk-...     # used by the agent and DeepEval's judge
```

### Run everything on Bedrock (no OpenAI key)

The agent and the DeepEval judge can both run on Amazon Bedrock — verified end to end:

```bash
pip install -e ".[bedrock]"             # adds langchain-aws + aiobotocore
export ACME_LLM_PROVIDER=bedrock        # agent on Bedrock
export DEEPEVAL_JUDGE=bedrock           # DeepEval judge on Bedrock
export AWS_REGION=us-east-1             # plus AWS credentials
# judge model override: DEEPEVAL_JUDGE_MODEL=...
```

## Run

```bash
python run.py "where is my order #1007?"
python -m evals.run_evals
```

## Compare

Run the native ([`../acme-support-agent-py-langgraph`](../acme-support-agent-py-langgraph))
and Ragas ([`../acme-support-agent-py-langgraph-ragas`](../acme-support-agent-py-langgraph-ragas))
variants on the same dataset to compare what each eval library tells you about the
identical agent.
