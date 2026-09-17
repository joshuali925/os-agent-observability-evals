# Acme Support Agent — Amazon Bedrock AgentCore Runtime

One clean, deployable flow: the Acme Support Agent hosted on **Amazon Bedrock
AgentCore Runtime**, instrumented with the OpenSearch GenAI SDK so every invocation
is one `invoke_agent` trace in your stack.

The runtime contract is a single `@app.entrypoint` function ([`agent.py`](agent.py)).
Everything else — the agent loop, tools, observability, dataset — is the same shared
core (`acme-shared`) as every other variant, so the code you eval locally is exactly
the code the runtime serves.

## Local development

Bring up the observability stack from [`../acme-support-agent`](../acme-support-agent)
(`docker compose up -d`), then:

```bash
# The GenAI SDK isn't on PyPI yet — install it from source first:
git clone https://github.com/opensearch-project/genai-observability-sdk-py ../genai-observability-sdk-py
pip install -e ../genai-observability-sdk-py

pip install -e ../acme-shared
pip install -e .
export AWS_REGION=us-east-1      # configure AWS credentials (env/profile/role)

# run the AgentCore dev server (same contract as the deployed runtime)
python agent.py
```

Invoke it locally:

```bash
curl -s -X POST http://localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "where is my order #1007?"}'
```

Traces flow to the local stack via `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`
(defaults to `http://localhost:4318/v1/traces`).

## Evaluate

```bash
python -m evals.run_evals
```

This evals the exact entrypoint code path that runs in production.

## Deploy to AgentCore Runtime

```bash
pip install -e ".[deploy]"

# vendor the shared core so the build context can see it, then configure + launch
cp -r ../acme-shared ./acme-shared
agentcore configure --entrypoint agent.py
agentcore launch
```

In the deployed runtime, set `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` to your in-VPC
OTel Collector. Auth and metrics follow the AWS-managed path in
[`../acme-support-agent/docs/production.md`](../acme-support-agent/docs/production.md).

## What's shared vs. specific

| Shared (from `acme-shared`) | Specific to this variant |
|---|---|
| tools, observability wiring, dataset, golden paths, criteria | the AgentCore entrypoint + Bedrock Converse loop ([`agent.py`](agent.py)), deploy flow |
