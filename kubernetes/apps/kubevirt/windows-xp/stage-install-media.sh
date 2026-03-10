#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 /path/to/windows-xp.iso [namespace] [claim]"
  exit 1
fi

iso_path="$1"
namespace="${2:-kubevirt}"
claim="${3:-windows-xp-install-media}"
pod="windows-xp-install-media-stage"
image="alpine:3.20"

if [[ ! -f "$iso_path" ]]; then
  echo "install media not found: $iso_path"
  exit 1
fi

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
    - name: stage
      image: $image
      command:
        - /bin/sh
        - -ec
        - |
          rm -f /media/disk.img
          touch /media/.stage-ready
          sleep 600
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsUser: 107
        runAsGroup: 107
        runAsNonRoot: true
      volumeMounts:
        - name: media
          mountPath: /media
  volumes:
    - name: media
      persistentVolumeClaim:
        claimName: $claim
EOF

kubectl -n "$namespace" wait --for=condition=Ready pod/"$pod" --timeout=120s >/dev/null
kubectl -n "$namespace" cp "$iso_path" "$pod:/media/disk.img"
kubectl -n "$namespace" exec "$pod" -- /bin/sh -ec 'sync && ls -lh /media/disk.img'
