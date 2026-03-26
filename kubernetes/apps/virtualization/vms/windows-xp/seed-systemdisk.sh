#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-kubevirt}"
claim="${2:-windows-xp-systemdisk}"
size="${3:-40G}"
pod="windows-xp-systemdisk-seed"
image="alpine:3.20"

cleanup() {
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  namespace: $namespace
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 107
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: seed
      image: $image
      command:
        - /bin/sh
        - -ec
        - |
          rm -f /rootdisk/disk.img
          truncate -s "$size" /rootdisk/disk.img
          sync
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsUser: 107
        runAsGroup: 107
        runAsNonRoot: true
      volumeMounts:
        - name: rootdisk
          mountPath: /rootdisk
  volumes:
    - name: rootdisk
      persistentVolumeClaim:
        claimName: $claim
EOF

kubectl -n "$namespace" wait --for=jsonpath='{.status.phase}'=Succeeded pod/"$pod" --timeout=120s >/dev/null
kubectl -n "$namespace" wait --for=jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}'=0 pod/"$pod" --timeout=120s >/dev/null
kubectl -n "$namespace" logs "$pod"
