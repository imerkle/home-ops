#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-kubevirt}"
network_name="${2:-lan-net}"
router_ip="${3:-192.168.10.1}"
test_ip="${4:-192.168.10.2/24}"
pod="lan-net-test"

cleanup() {
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  namespace: $namespace
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name":"$network_name","namespace":"$namespace","interface":"net1"}]'
spec:
  restartPolicy: Never
  containers:
    - name: toolbox
      image: nicolaka/netshoot:latest
      command: ["/bin/sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          add: ["NET_ADMIN", "NET_RAW"]
          drop: ["ALL"]
        runAsUser: 0
        seccompProfile:
          type: RuntimeDefault
EOF

kubectl -n "$namespace" wait --for=condition=Ready pod/"$pod" --timeout=120s >/dev/null

echo "== Pod =="
kubectl -n "$namespace" get pod "$pod" -o wide

echo
echo "== Static IP and ARP test =="
kubectl -n "$namespace" exec "$pod" -- sh -lc "
  ip addr flush dev net1
  ip addr add '$test_ip' dev net1
  ip link set net1 up
  ip addr show net1
  echo
  arping -c 3 -I net1 '$router_ip'
"

echo
echo "== DHCP test =="
kubectl -n "$namespace" exec "$pod" -- sh -lc "
  ip addr flush dev net1
  ip link set net1 up
  udhcpc -i net1 -n -q -t 3 -T 2 2>&1 || true
"
