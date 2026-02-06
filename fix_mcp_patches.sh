#!/bin/bash

# 1. Patch the Backend to point to the actual Envoy Pod IP
# This fixes the connection from Envoy to the sidecar proxy.
# We first retrieve the Envoy Pod IP because 127.0.0.1 is blocked by the validation webhook.
ENVOY_POD_IP=$(kubectl get pod -n network -l app.kubernetes.io/name=envoy-ai -o jsonpath='{.items[0].status.podIP}')
echo "Envoy Pod IP: $ENVOY_POD_IP"

kubectl patch backend -n flux-system flux-system-mcp-unified-mcp-proxy --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/endpoints/0/ip/address\", \"value\": \"$ENVOY_POD_IP\"}]"

# 2. Patch the Envoy Filter Config Secret
# This fixes the sidecar proxy's upstream connection by bypassing the broken local listener (127.0.0.1:10088)
# and pointing directly to the Flux MCP service.
kubectl patch secret -n network envoy-ai-network --type='merge' -p "{\"stringData\":{\"filter-config.yaml\":\"backends:\\n- modelNameOverride: \\\"\\\"\\n  name: flux-system/flux-mcp-backend/route/flux-mcp/rule/0/ref/0\\n  schema:\\n    name: OpenAI\\n    prefix: v1\\n    version: v1\\nmcpConfig:\\n  backendListenerAddr: http://flux-operator-mcp.flux-system.svc.cluster.local:9090\\n  routes:\\n  - backends:\\n    - name: flux-mcp-backend\\n      path: /mcp\\n    name: flux-system/mcp-unified\\nuuid: 79135ab5-1f1d-4055-a7c4-2929af59557a\\nversion: dev\\n\"}}"
