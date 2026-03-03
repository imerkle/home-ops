---
name: Cilium Network Policy Connectivity Troubleshooting
description: A generalized guide on how to troubleshoot and configure CiliumNetworkPolicies to allow communication between different applications.
---

# Troubleshooting App Connectivity with CiliumNetworkPolicies

When two applications in your Kubernetes cluster need to communicate but fail, the issue is often related to a **CiliumNetworkPolicy (NetPol)** blocking the traffic. This usually happens because the labels specified in the NetPol do not exactly match the actual labels applied to the running pods.

This skill describes the generalized process for identifying and resolving these connectivity issues.

## 1. Identify the Communication Requirements

First, identify the **Source Application** and the **Target Application**.
- Determine which application initiates the connection (egress).
- Determine which application receives the connection (ingress).
- Identify the specific **Port(s)** and **Protocol(s)** required for this communication (e.g., TCP 8008, TCP 8000, TCP 5432).

## 2. Verify Actual Pod Labels

Helm charts and App Templates often inject standard `app.kubernetes.io` labels, but they can vary between `instance`, `name`, `component`, or `part-of`.

**Do not assume what the labels are based on the release name.** Instead, inspect the running pods.

Run the following command to see the labels of the pods in the relevant namespace:
```bash
kubectl get pods -n <namespace> --show-labels
```
*(Or filter by a known substring using `grep -E "app1|app2"`).*

Identify the unique and immutable labels that identify the **Source** and the **Target**.
- Example Source Label: `app.kubernetes.io/name=mautrix-whatsapp`
- Example Target Label: `app.kubernetes.io/part-of=matrix-stack`

## 3. Compare the Actual Labels with the Network Policy

Review the existing `CiliumNetworkPolicy` YAML files for both applications. You need to check three critical areas:

### A. The Endpoint Selector (`spec.endpointSelector`)
This section determines **which pods this policy applies to**. If this is wrong, the policy does nothing for your app.
```yaml
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/part-of: matrix-stack # <--- MUST match the actual application pod label
```

### B. Ingress Rules (`spec.ingress`)
If your app is receiving traffic, it needs an ingress rule allowing the source. Check the `fromEndpoints` and `toPorts`.
```yaml
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: mautrix-whatsapp # <--- MUST match the SOURCE pod label
      toPorts:
        - ports:
            - port: "8008"
              protocol: TCP
```

### C. Egress Rules (`spec.egress`)
If your app is initiating traffic, it needs an egress rule allowing it to reach the target. Check the `toEndpoints` and `toPorts`.
```yaml
  egress:
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/part-of: matrix-stack # <--- MUST match the TARGET pod label
      toPorts:
        - ports:
            - port: "8008"
              protocol: TCP
```

## 4. Resolve Mismatches

If the actual labels from **Step 2** do not match the labels in the NetPols from **Step 3**, update your infrastructure-as-code (e.g., Flux GitOps repository `netpol.yaml` files).

### Common Mistakes
- Using `app.kubernetes.io/instance: matrix` when the pod actually uses `app.kubernetes.io/part-of: matrix-stack`.
- Using `app.kubernetes.io/name: matrix-synapse` when the pod actually uses `app.kubernetes.io/name: synapse-main`.
- Forgetting to specify the necessary `toPorts` for the target service, which defaults to blocking if a ports block is introduced but incomplete.

## 5. Apply and Test

Once you fix the `matchLabels` to perfectly align with the actual running pods, commit your changes.
Wait for Flux (or your GitOps tool) to reconcile the new CiliumNetworkPolicy, and verify that the two applications can now successfully communicate over the specified ports.
