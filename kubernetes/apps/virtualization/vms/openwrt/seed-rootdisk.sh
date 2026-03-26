#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-kubevirt}"
claim="${2:-openwrt-state}"
source_image="${3:-containercraft/openwrt:24}"
source_path="${4:-/disk/openwrt-24.qcow2}"
converter_image="${5:-quay.io/kubevirt/virt-launcher:v1.7.1}"
pod="openwrt-rootdisk-seed"

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
  initContainers:
    - name: stage-source
      image: $source_image
      command:
        - /bin/sh
        - -ec
        - |
          cp "$source_path" /workspace/source.qcow2
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsUser: 107
        runAsGroup: 107
        runAsNonRoot: true
      volumeMounts:
        - name: workspace
          mountPath: /workspace
  containers:
    - name: seed
      image: $converter_image
      command:
        - /bin/sh
        - -ec
        - |
          rm -f /rootdisk/disk.img
          rm -f /rootdisk/disk.qcow2
          qemu-img convert -f qcow2 -O raw /workspace/source.qcow2 /rootdisk/disk.img
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
        - name: workspace
          mountPath: /workspace
  volumes:
    - name: rootdisk
      persistentVolumeClaim:
        claimName: $claim
    - name: workspace
      emptyDir: {}
EOF

kubectl -n "$namespace" wait --for=jsonpath='{.status.phase}'=Succeeded pod/"$pod" --timeout=120s >/dev/null
kubectl -n "$namespace" wait --for=jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}'=0 pod/"$pod" --timeout=120s >/dev/null
kubectl -n "$namespace" logs "$pod"
