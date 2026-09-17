#!/usr/bin/env bash
# Blog Part 4: verify the agent's telemetry actually landed correctly.
# Run this AFTER running the agent at least once.
set -euo pipefail

OS_URL="${OPENSEARCH_URL:-https://localhost:9200}"
OS_USER="${OPENSEARCH_USERNAME:-admin}"
OS_PASS="${OPENSEARCH_PASSWORD:-My_password_123!@#}"

ppl() {
  curl -sk -u "$OS_USER:$OS_PASS" -X POST "$OS_URL/_plugins/_ppl" \
    -H 'Content-Type: application/json' -d "{\"query\": \"$1\"}"
}

echo "==> 1. Trace indices exist"
curl -sk -u "$OS_USER:$OS_PASS" "$OS_URL/_cat/indices?v" | grep -E "otel-v1-apm-span" \
  || { echo "❌ no otel-v1-apm-span-* index — telemetry hasn't landed"; exit 1; }

echo
echo "==> 2. Span count (must be > 0)"
ppl "source=otel-v1-apm-span-* | stats count()"

echo
echo "==> 3. Operation types present (want invoke_agent, chat, execute_tool)"
ppl "source=otel-v1-apm-span-* | stats count() by serviceName, \`span.attributes.gen_ai@operation@name\`"

echo
echo "==> 4. Tool calls captured"
ppl "source=otel-v1-apm-span-* | where \`span.attributes.gen_ai@operation@name\` = 'execute_tool' | stats count() by \`span.attributes.gen_ai@tool@name\`"

echo
echo "==> 5. Token usage attached to chat spans"
ppl "source=otel-v1-apm-span-* | where cast(\`span.attributes.gen_ai@usage@input_tokens\` as int) > 0 | stats sum(cast(\`span.attributes.gen_ai@usage@input_tokens\` as int)) as in_tokens, sum(cast(\`span.attributes.gen_ai@usage@output_tokens\` as int)) as out_tokens by \`span.attributes.gen_ai@request@model\`"

echo
echo "✅ If all five returned data, instrumentation is healthy."
