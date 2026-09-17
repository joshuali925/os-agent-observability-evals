# Observe & debug — PPL query cookbook (Blog Part 5)

Copy-paste PPL queries for exploring the Acme agent's traces. All use the local
stack defaults (`admin` / `My_password_123!@#`, `-k` to skip TLS verification).
Run them via the PPL API or paste the query body into OpenSearch Dashboards →
Observability → PPL.

Data Prepper flattens span attributes into the `otel-v1-apm-span-*` index by
prefixing them with `span.attributes.` and replacing dots inside the attribute key
with `@` — so the OTel attribute `gen_ai.operation.name` is queried as
`` `span.attributes.gen_ai@operation@name` ``, resource attributes use
`resource.attributes.…`, and event attributes use `events.attributes.…`. The
queries below use those flattened names.

Set these once:

```bash
OS=https://localhost:9200
AUTH='admin:My_password_123!@#'
ppl() { curl -sk -u "$AUTH" -X POST "$OS/_plugins/_ppl" -H 'Content-Type: application/json' -d "{\"query\": \"$1\"}"; }
```

## Reconstruct one trace (the full reasoning tree)

```bash
ppl "source=otel-v1-apm-span-* | where traceId = '<TRACE_ID>' | fields spanId, parentSpanId, name, \`span.attributes.gen_ai@operation@name\`, durationInNanos | sort startTime"
```

## Recent agent invocations

```bash
ppl "source=otel-v1-apm-span-* | where \`span.attributes.gen_ai@operation@name\` = 'invoke_agent' | fields traceId, \`span.attributes.gen_ai@agent@name\`, durationInNanos, startTime | sort - startTime | head 20"
```

## Slow agent invocations (> 5s)

```bash
ppl "source=otel-v1-apm-span-* | where \`span.attributes.gen_ai@operation@name\` = 'invoke_agent' AND durationInNanos > 5000000000 | fields traceId, \`span.attributes.gen_ai@agent@name\`, durationInNanos | sort - durationInNanos"
```

## Error spans (status.code = 2 is ERROR in OTel)

```bash
ppl "source=otel-v1-apm-span-* | where \`status.code\` = 2 | fields traceId, serviceName, name, \`events.attributes.exception@message\` | sort - startTime | head 20"
```

## Token usage by model (cost signal)

```bash
ppl "source=otel-v1-apm-span-* | where cast(\`span.attributes.gen_ai@usage@input_tokens\` as int) > 0 | stats sum(cast(\`span.attributes.gen_ai@usage@input_tokens\` as int)) as in_tokens, sum(cast(\`span.attributes.gen_ai@usage@output_tokens\` as int)) as out_tokens by \`span.attributes.gen_ai@request@model\`"
```

## Tool call inspection (arguments + results)

```bash
ppl "source=otel-v1-apm-span-* | where \`span.attributes.gen_ai@operation@name\` = 'execute_tool' | fields \`span.attributes.gen_ai@tool@name\`, \`span.attributes.gen_ai@tool@call@arguments\`, \`span.attributes.gen_ai@tool@call@result\`, durationInNanos | sort - startTime | head 20"
```

## Multi-turn conversation tracking

```bash
ppl "source=otel-v1-apm-span-* | where \`span.attributes.gen_ai@conversation@id\` != '' | stats count() as turns, sum(cast(\`span.attributes.gen_ai@usage@input_tokens\` as int)) as in_tokens by \`span.attributes.gen_ai@conversation@id\`"
```

## Eval scores (Blog Part 6) — find low-scoring runs

```bash
# score() emits one `evaluation` span per metric, carrying gen_ai.evaluation.name
# and gen_ai.evaluation.score.value. Group by metric to see the score distribution:
ppl "source=otel-v1-apm-span-* | where \`span.attributes.gen_ai@operation@name\` = 'evaluation' | stats count() as n by \`span.attributes.gen_ai@evaluation@name\`, \`span.attributes.gen_ai@evaluation@score@value\`"
```

## Detect the "looped & hallucinated" failure mode

A trace with multiple `chat` spans and no `execute_tool` is the classic bad case:

```bash
ppl "source=otel-v1-apm-span-* | eval is_chat=if(\`span.attributes.gen_ai@operation@name\`='chat',1,0), is_tool=if(\`span.attributes.gen_ai@operation@name\`='execute_tool',1,0) | stats sum(is_chat) as chats, sum(is_tool) as tools by traceId | where chats > 2 AND tools = 0"
```
