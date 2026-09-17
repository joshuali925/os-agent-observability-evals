# From day one to healthy production: instrumenting and evaluating AI agents with OpenSearch

You shipped an agent. Maybe it's a prototype on your laptop, maybe it's already taking
production traffic. Either way the same question shows up: **is it actually doing what I
think it's doing?** Which tool did it call? Why did that request cost $0.40? Why did it loop
three times before answering? And the harder one — *is it getting better or worse as I change
the prompt?*

OpenSearch's AI observability stack answers those questions with one trace store for
everything your agent does — every model call, every tool execution, every retrieval — plus
the evaluation tooling to score whether the agent did the *right* thing, not just whether it
returned 200 OK.

This tutorial walks the whole journey: **instrument → verify → observe → evaluate → monitor →
close the loop.** We'll thread one example agent through all of it, and show the same setup
across every framework the stack supports.

---

## Where are you today?

You don't need to read this top to bottom. Find your row and jump in.

| You are… | Start at | First move |
|---|---|---|
| **Building a new agent** | Part 1 | Define goals, then instrument from line one |
| **Have an agent in dev** | Part 2 | Stand up the stack, add `register()` |
| **Have an agent in production** | Part 2 → **Part 6** | Retrofit instrumentation, then **monitor first** — evals come after you can see live health |

And on the stack axis:

| Your runtime | Path |
|---|---|
| **Python** | Native SDK (`opensearch-genai-observability-sdk-py`) — the spine of this tutorial |
| **TypeScript / Node** | Native SDK ([`@opensearch-project/genai-observability-sdk-ts`](https://github.com/opensearch-project/genai-observability-sdk-ts)) — full parity with Python |

---

## The example app: Acme Support Agent

Everything below uses one agent so you can follow it end to end and run it yourself. It's a
customer-support agent for a fictional store, **Acme**. We picked it because it exercises every
span type the stack cares about while staying simple enough to grade:

- **`invoke_agent`** — the top-level "handle this customer question" span
- **`chat`** — the LLM reasoning calls
- **`execute_tool`** — three deterministic tools:
  - `lookup_order(order_id)` → returns status, items, ship date
  - `check_inventory(sku)` → returns stock count
  - `search_policy(query)` → RAG over a returns/shipping policy doc
- **`retrieval` / `embeddings`** — the policy search path

Because the tools return fixed data, evaluation is objective: *did the agent call
`lookup_order` with `1007` when asked "where's my order #1007?"* — yes or no. And there's a
clear **golden path** for that question (`lookup_order` → answer, no detours), which we'll use
for trajectory comparison later.

The important part for this tutorial: **the agent logic and the observability code are written
once.** Only the model/tool-calling layer changes per framework — and the SDK instruments all
of them the same way.

> **Run it yourself.** Everything in this post is a working repo:
> [github.com/anirudha/os-agent-observability-evals](https://github.com/anirudha/os-agent-observability-evals).
> The main `acme-support-agent/` folder shows every framework in one place. If you'd rather start
> from a single focused flow, there are standalone variants that all share one core
> (`acme-shared/` — the tools, observability wiring, dataset, and eval criteria), so the only
> thing that changes between them is the framework or the eval library:
>
> | Variant | Framework | Eval layer |
> |---|---|---|
> | `acme-support-agent-py-langgraph` | LangGraph | native SDK |
> | `acme-support-agent-py-strands` | Strands Agents | native SDK |
> | `acme-support-agent-py-langgraph-deepeval` | LangGraph | DeepEval |
> | `acme-support-agent-py-langgraph-ragas` | LangGraph | Ragas |
> | `acme-support-agent-agentcore` | Bedrock AgentCore Runtime | native SDK |

---

## Part 1 — Define goals first

Before a line of instrumentation, decide what "good" means. This isn't process for its own
sake — your goals tell you which spans and attributes *must* exist, and they become your eval
criteria later.

For Acme Support Agent:

| Goal | Signal we'll need |
|---|---|
| **Answers correctly** | Eval score on final answer vs. expected |
| **Calls the right tool** | `execute_tool` spans with `gen_ai.tool.name` + arguments |
| **Stays cheap** | `gen_ai.usage.input_tokens` / `output_tokens` per request |
| **Stays fast** | Span `durationInNanos`, end to end |
| **Doesn't loop** | Count of `chat` spans per `invoke_agent` trace |

Failure modes we're explicitly watching for: wrong tool selection, hallucinated order details
when `lookup_order` wasn't called, and runaway reasoning loops that burn tokens.

Write these down. Part 6 turns each row into an automated check.

---

## Part 2 — Stand up the stack

Local first. One Docker Compose brings up the whole pipeline: OpenSearch, the OpenTelemetry
Collector, Data Prepper, Prometheus, and OpenSearch Dashboards.

```bash
git clone https://github.com/anirudha/os-agent-observability-evals
cd os-agent-observability-evals/acme-support-agent
docker compose up -d
```

The pipeline your telemetry will flow through:

```
your agent → OTel Collector (normalize) → Data Prepper (service maps, correlation)
           → OpenSearch (store) → Dashboards (analyze)
                                   Prometheus (metrics)
```

Quick sanity check that the cluster is up:

```bash
curl -sk -u admin:'My_password_123!@#' https://localhost:9200/_cluster/health?pretty
# expect "status": "green" or "yellow"
```

Ports you'll use: OTel Collector `4318` (HTTP) / `4317` (gRPC), OpenSearch `9200`, Dashboards
`5601`, Prometheus `9090`.

**For production**, you don't change your code — you swap the endpoint and auth to
**Amazon OpenSearch Service** + **Amazon Managed Service for Prometheus**. Same SDK, same
spans. We'll cover that in Part 7.

---

## Part 3 — Instrument

This is the "meet you where you are" core. Pick your runtime.

### 3a. Python — the native SDK

Install the SDK with the extra for whatever framework you already run. You don't rewrite your
agent; you add auto-instrumentation for the library you're using. The SDK isn't published to
PyPI yet, so install it from source and pick the extra that matches your stack:

```bash
git clone https://github.com/opensearch-project/genai-observability-sdk-py

pip install "./genai-observability-sdk-py[openai]"
pip install "./genai-observability-sdk-py[anthropic]"
pip install "./genai-observability-sdk-py[bedrock]"
pip install "./genai-observability-sdk-py[langchain]"
pip install "./genai-observability-sdk-py[llamaindex]"

# or everything, for a multi-framework agent
pip install "./genai-observability-sdk-py[all]"
```

Auto-instrumentation covers OpenAI (and OpenAI Agents), Anthropic, Bedrock, Google AI,
LangChain, LlamaIndex, Cohere, Mistral, Groq, Ollama, CrewAI, and vector stores like Pinecone,
Weaviate, and Chroma — 20+ libraries in all.

**One call at startup wires up the whole OTel pipeline:**

```python
from opensearch_genai_observability_sdk_py import register, observe, enrich, Op

register(
    endpoint="http://localhost:4318/v1/traces",  # Data Prepper / OTel Collector
    service_name="acme-support-agent",
    # auto_instrument=True by default — discovers installed instrumentors
)
```

Now the framework-specific LLM and tool calls are traced automatically. You add **one
decorator** on your agent entry point so the whole run is stitched under a single
`invoke_agent` trace, and `enrich()` to tag the model:

```python
@observe(op=Op.INVOKE_AGENT)
def handle_support_question(question: str, conversation_id: str) -> str:
    enrich(
        model="gpt-4o",
        provider="openai",
        session_id=conversation_id,   # sets gen_ai.conversation.id; ties multi-turn sessions together
    )
    # your existing agent loop — unchanged.
    # auto-instrumentation emits chat + execute_tool + retrieval spans for you.
    return run_agent(question)
```

That's the entire integration. The agent body is the same code you already had.

**Per-framework note — the only thing that differs is the agent body:**

- **OpenAI / OpenAI Agents** — `client.chat.completions.create(...)` with `tools=[...]`; the
  `[openai]` extra traces both the chat calls and tool dispatch.
- **Anthropic** — `client.messages.create(...)` with `tools=[...]`; install `[anthropic]`.
- **Bedrock** — `bedrock_runtime.converse(...)` with `toolConfig`; install `[bedrock]`.
- **LangChain / LangGraph** — your `AgentExecutor`, LCEL chain, or `create_react_agent` graph;
  install `[langchain]` and the callback handler is registered automatically.
- **LlamaIndex** — your `ReActAgent` / query engine; install `[llamaindex]`.
- **Strands Agents** — hand the SDK your tools + system prompt and it runs the loop; Strands
  also emits OTel spans natively, so its telemetry composes with the OpenSearch SDK.

In every case `register()` + `@observe` is identical. Acme's three tools and goals don't
change — only the SDK call to the model does. That's exactly how the
[standalone variants](https://github.com/anirudha/os-agent-observability-evals) are built: one
shared `acme-shared/` core (tools, observability, dataset, criteria), and a per-variant agent
file that's the only thing that differs. Compare
[`acme_shared/langgraph_agent.py`](https://github.com/anirudha/os-agent-observability-evals/blob/main/acme-shared/acme_shared/langgraph_agent.py)
with the Strands
[`strands_agent.py`](https://github.com/anirudha/os-agent-observability-evals/blob/main/acme-support-agent-py-strands/strands_agent.py)
to see how little changes.

> **Deploying to a managed runtime?** The
> [`acme-support-agent-agentcore`](https://github.com/anirudha/os-agent-observability-evals/tree/main/acme-support-agent-agentcore)
> variant wraps the same agent in an **Amazon Bedrock AgentCore Runtime** `@app.entrypoint`.
> `register()` is called once at cold start, so every invocation the runtime serves is one
> `invoke_agent` trace — instrumentation survives the move from laptop to managed endpoint
> unchanged.

### 3b. TypeScript / Node — the native SDK

The TypeScript SDK is published and has full parity with Python:
[`@opensearch-project/genai-observability-sdk-ts`](https://github.com/opensearch-project/genai-observability-sdk-ts)
— `register`, `observe`, `enrich`, `score`, `Op`, the lot.

```bash
npm install @opensearch-project/genai-observability-sdk-ts @opentelemetry/api
```

`register()` once at startup (import it before your agent so the pipeline is live):

```typescript
import { register } from "@opensearch-project/genai-observability-sdk-ts";

await register({
  endpoint: "http://localhost:4318/v1/traces",
  serviceName: "acme-support-agent",
});
```

Then `observe()` wraps the agent and the tools — and, like the Python decorator, it
auto-captures a tool's arguments and return value into
`gen_ai.tool.call.arguments` / `result`:

```typescript
import { observe, enrich, Op } from "@opensearch-project/genai-observability-sdk-ts";

// a tool — observe() captures args + result automatically
export const lookupOrder = observe(
  { name: "lookup_order", op: Op.EXECUTE_TOOL },
  function lookupOrder(orderId: string) {
    return ORDERS[orderId] ?? { error: "order_not_found", orderId };
  },
);

// the agent entry point — one invoke_agent span over the whole turn
export const handleSupportQuestion = observe(
  { name: "acme-support-agent", op: Op.INVOKE_AGENT },
  async function handleSupportQuestion(question: string, conversationId: string) {
    enrich({ model: "gpt-4o", provider: "openai", sessionId: conversationId });
    return await runAgent(question);  // chat + execute_tool spans emitted for you
  },
);
```

That's the same `register()` + `observe()` + `enrich()` flow as Python — the only difference
is the language. Wrap each model call with `observe({ op: Op.CHAT })` and `enrich()` the token
usage onto it, exactly as in 3a.

---

## Part 4 — Verify instrumentation

Don't move on until data is actually landing correctly. Three checks.

**1. Indices exist and are filling up:**

```bash
curl -sk -u admin:'My_password_123!@#' https://localhost:9200/_cat/indices?v
# look for otel-v1-apm-span-*
```

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | stats count()"}'
# count must be > 0 after you run the agent once
```

**2. Spans carry the GenAI attributes and the right shape.** Send Acme one question
("where's my order #1007?") and confirm you see the expected operation types. (Data
Prepper flattens each OTel span attribute into the index as
`` `span.attributes.<key-with-dots-as-@>` `` — so `gen_ai.operation.name` is queried
as `` `span.attributes.gen_ai@operation@name` ``.)

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | stats count() by serviceName, `span.attributes.gen_ai@operation@name`"}'
```

You want to see `invoke_agent`, `chat`, and `execute_tool` for `acme-support-agent`. The
healthy shape is: **one `invoke_agent` → one or more `chat` → an `execute_tool`
(`lookup_order`), all sharing one `traceId`, with token usage attached to the chat spans.**

**3. The Collector is accepting and exporting, not dropping:**

```bash
curl -s http://localhost:8888/metrics | grep -E "otelcol_receiver_accepted_spans|otelcol_exporter_send_failed_spans"
# accepted should climb; send_failed should stay at 0
```

If counts are zero, the [stack-health troubleshooting](#) path is: check the Collector
metrics, then `docker compose logs data-prepper | grep -i error`, then confirm your agent is
pointed at `localhost:4318`.

---

## Part 5 — Observe and debug

Now the payoff: seeing what your agent actually did.

**OpenSearch Dashboards** is where you explore — trace tree / DAG / timeline views,
the service map, and ad-hoc PPL. A few queries you'll reach for constantly:

Reconstruct a single trace (the whole reasoning tree for one question):

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | where traceId = '\''<TRACE_ID>'\'' | fields spanId, parentSpanId, name, `span.attributes.gen_ai@operation@name`, durationInNanos | sort startTime"}'
```

Find slow agent invocations:

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | where `span.attributes.gen_ai@operation@name` = '\''invoke_agent'\'' AND durationInNanos > 5000000000 | fields traceId, `span.attributes.gen_ai@agent@name`, durationInNanos | sort - durationInNanos"}'
```

Find error spans (`status.code = 2` is ERROR in OTel):

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | where `status.code` = 2 | fields traceId, serviceName, name, `events.attributes.exception@message` | sort - startTime | head 20"}'
```

Token usage by model (your cost signal):

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | where cast(`span.attributes.gen_ai@usage@input_tokens` as int) > 0 | stats sum(cast(`span.attributes.gen_ai@usage@input_tokens` as int)) as in, sum(cast(`span.attributes.gen_ai@usage@output_tokens` as int)) as out by `span.attributes.gen_ai@request@model`"}'
```

Track a multi-turn conversation (Acme follow-ups like "can I return it?"):

```bash
curl -sk -u admin:'My_password_123!@#' \
  -X POST https://localhost:9200/_plugins/_ppl \
  -H 'Content-Type: application/json' \
  -d '{"query": "source=otel-v1-apm-span-* | where `span.attributes.gen_ai@conversation@id` != '\'''\'' | stats count() as turns, sum(cast(`span.attributes.gen_ai@usage@input_tokens` as int)) as in_tokens by `span.attributes.gen_ai@conversation@id`"}'
```

This is also where you catch the failure modes from Part 1: a trace with three `chat` spans and
no `execute_tool` is the "looped and hallucinated" case made visible.

---

## Part 6 — Evaluate

Observing tells you *what* happened. Evaluation tells you whether it was *right* — and whether
your last prompt change helped or hurt. The Python SDK has this built in, so your eval scores
live in the same trace store as everything else.

**Score a run inline** with `score()` — attach a judgment to the live trace:

```python
from opensearch_genai_observability_sdk_py import score

@observe(op=Op.INVOKE_AGENT)
def handle_support_question(question: str, conversation_id: str) -> str:
    answer = run_agent(question)
    score(
        name="answer_correctness",
        value=judge_answer(question, answer),   # 0.0–1.0, e.g. an LLM-as-judge
    )
    return answer
```

**Build a dataset from real traces.** This is the trick that makes evals cheap: your hardest
test cases are the failures already sitting in OpenSearch. Pull the traces where the agent
erred or looped, label the expected behavior, and you have a regression suite grounded in real
traffic — plus a handful of golden cases like "where's order #1007? → `lookup_order` → correct
status."

**Run the suite with `evaluate()` / `Benchmark`** to score the whole dataset at once and track
the trend as you iterate:

- **LLM-as-judge** for the fuzzy criteria (was the answer correct, polite, grounded?).
- **Golden Path trajectory comparison** for the structural ones: did the agent take the
  expected tool path, or wander? For Acme's order-status question the golden trajectory is
  exactly `invoke_agent → lookup_order → answer`. Any extra `chat` loops or a `search_policy`
  detour shows up as a trajectory mismatch.

The loop: **run evals → read the failures in Dashboards → fix the prompt/tools → re-run.**
Because scores are emitted as spans, "did v2 of the prompt regress on cost or correctness?" is
just another PPL query over your eval runs.

### Bring your own eval library

Already invested in **DeepEval**, **Ragas**, Promptfoo, or OpenAI Evals? You don't have to
choose between them and the observability stack — emit their results as `score()` calls so the
numbers land next to your traces instead of in a separate silo.

The repo shows this twice, running the **identical LangGraph agent and dataset** through two
different eval libraries:

- [`acme-support-agent-py-langgraph-deepeval`](https://github.com/anirudha/os-agent-observability-evals/tree/main/acme-support-agent-py-langgraph-deepeval)
  — DeepEval's `AnswerRelevancyMetric` + `ToolCorrectnessMetric`, emitted as
  `deepeval.*` scores.
- [`acme-support-agent-py-langgraph-ragas`](https://github.com/anirudha/os-agent-observability-evals/tree/main/acme-support-agent-py-langgraph-ragas)
  — Ragas' `AspectCritic("correctness")` + tool-call accuracy, emitted as `ragas.*` scores.

The pattern is the same in both:

```python
from acme_shared import score  # the SDK's score(), re-exported

result = deepeval_metric.measure(test_case)   # or ragas single_turn_score(...)
score(name="deepeval.answer_relevancy", value=float(result))   # lands on the live trace
```

Because the dataset and golden paths are shared, you can run the native, DeepEval, and Ragas
runners back to back and compare what each tells you about the same agent. For a greenfield
agent the native path keeps everything in one place; for an existing eval pipeline, this is how
you keep your library and still get one trace store.

---

## Part 7 — Ship and monitor production

A healthy production agent needs *continuous* signals, not a one-time eval pass. Going to
production is a config change, not a code change: point `register()` at **Amazon OpenSearch
Service** and your metrics at **Amazon Managed Service for Prometheus** — the spans and queries
are identical, only the endpoint and auth (SigV4) differ.

```python
register(
    endpoint="https://<otel-collector-in-your-vpc>:4318/v1/traces",
    service_name="acme-support-agent",
)
```

If you deploy to a managed runtime like **Bedrock AgentCore**, this is the only change — the
[AgentCore variant](https://github.com/anirudha/os-agent-observability-evals/tree/main/acme-support-agent-agentcore)
calls `register()` once at cold start and sets `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` to the
in-VPC collector, so the same `invoke_agent` traces you debugged locally now flow from
production.

What to watch once you're live:

- **RED metrics** — Rate, Errors, Duration — per agent and **per tool**. A spike in
  `lookup_order` error rate or latency is your earliest warning of an upstream breakage.
- **Cost / token budgets** — the token sums from Part 5, now alerting when a model's daily
  spend crosses a threshold.
- **SLOs / SLIs + error budgets + burn-rate alerts** — define "95% of support answers in under
  4s" as an SLO, back it with Prometheus recording rules, and alert on burn rate so you hear
  about degradation before customers do.
- **Online evaluation** — keep calling `score()` on a sample of live traffic. Offline evals
  catch regressions before deploy; online evals catch the drift and edge cases your dataset
  never imagined.

---

## Part 8 — Close the loop

This is the step that separates a one-time audit from a *healthy* production agent:

```
production traces  →  curate the surprising/failing ones into your dataset  →  re-evaluate
        ↑                                                                          │
        └──────────────────────── ship the fix ────────────────────────────────────┘
```

The failures and weird edge cases your live agent hits in Part 7 become new rows in the Part 6
dataset. Each loop your regression suite gets sharper and more grounded in reality, and the
agent measurably improves instead of drifting. Same trace store, same `score()`, same PPL — the
journey is a loop, not a line.

---

## Recap

| Part | What you did | Acme made it concrete by… |
|---|---|---|
| 1 | Defined goals → eval criteria | correctness, right-tool, cost, latency, no-loops |
| 2 | Stood up the stack locally | one `docker compose up` |
| 3 | Instrumented your framework | `register()` + `@observe`, any of 20+ libs |
| 4 | Verified data lands correctly | `invoke_agent → chat → execute_tool` by `traceId` |
| 5 | Observed and debugged | trace trees, slow/error spans, token usage |
| 6 | Evaluated against a dataset | `score()`, golden-path for order #1007 — native, DeepEval, or Ragas |
| 7 | Monitored production | RED, cost budgets, SLOs, online eval |
| 8 | Closed the loop | prod traces → dataset → re-eval |

Start at your row in the table at the top. The fastest path to "is my agent healthy?" is one
`register()` call and a single trace — everything else builds from there.

The full, runnable code — the main multi-framework tutorial plus the five standalone variants
(LangGraph, Strands, LangGraph+DeepEval, LangGraph+Ragas, and Bedrock AgentCore Runtime) — is at
**[github.com/anirudha/os-agent-observability-evals](https://github.com/anirudha/os-agent-observability-evals)**.
Clone it, `docker compose up`, and run the variant that matches your stack.
```
