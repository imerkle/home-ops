#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 /path/to/windows-xp.ova [namespace] [claim]"
  exit 1
fi

vmdk_path="$1"
namespace="${2:-kubevirt}"
claim="${3:-windows-xp-systemdisk}"
pod="windows-xp-vmdk-import"
converter_image="${4:-quay.io/kubevirt/virt-launcher:v1.7.1}"

if [[ ! -f "$vmdk_path" ]]; then
  echo "VMDK not found: $vmdk_path"
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required"
  exit 1
fi

tmpdir="$(mktemp -d)"

cleanup() {
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
  rm -rf "$tmpdir"
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
    - name: import
      image: $converter_image
      command:
        - /bin/sh
        - -ec
        - |
          touch /workspace/.ready
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

kubectl -n "$namespace" wait --for=condition=Ready pod/"$pod" --timeout=120s >/dev/null
kubectl -n "$namespace" cp "$vmdk_path" "$pod:/workspace/source.vmdk"
kubectl -n "$namespace" exec "$pod" -- /bin/sh -ec '
  rm -f /rootdisk/disk.img
  qemu-img info /workspace/source.vmdk
  qemu-img convert -f vmdk -O raw /workspace/source.vmdk /rootdisk/disk.img
  sync
  ls -lh /rootdisk/disk.img
'
