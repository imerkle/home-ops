#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 /path/to/windows-xp.ova|/path/to/windows-xp.vmdk [namespace] [claim]"
  exit 1
fi

source_path="$1"
namespace="${2:-kubevirt}"
claim="${3:-windows-xp-systemdisk}"
pod="windows-xp-vmdk-import"
converter_image="${4:-quay.io/kubevirt/virt-launcher:v1.7.1}"

if [[ ! -f "$source_path" ]]; then
  echo "source not found: $source_path"
  exit 1
fi

tmpdir="$(mktemp -d)"
vmdk_path=""

cleanup() {
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
  rm -rf "$tmpdir"
}

trap cleanup EXIT

case "$source_path" in
  *.ova)
    if ! command -v tar >/dev/null 2>&1; then
      echo "tar is required for OVA input"
      exit 1
    fi
    vmdk_name="$(tar -tf "$source_path" | awk '/\.vmdk$/ { print; exit }')"
    if [[ -z "$vmdk_name" ]]; then
      echo "No VMDK found inside OVA: $source_path"
      exit 1
    fi
    tar -xf "$source_path" -C "$tmpdir" "$vmdk_name"
    vmdk_path="$tmpdir/$vmdk_name"
    ;;
  *.vmdk)
    vmdk_path="$source_path"
    ;;
  *)
    echo "unsupported input: $source_path"
    echo "expected a .ova or .vmdk file"
    exit 1
    ;;
esac

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
  echo "== source image =="
  qemu-img info /workspace/source.vmdk
  qemu-img convert -f vmdk -O raw /workspace/source.vmdk /rootdisk/disk.img
  sync
  echo "== converted image =="
  qemu-img info /rootdisk/disk.img
  ls -lh /rootdisk/disk.img
  if command -v fdisk >/dev/null 2>&1; then
    echo "== partition table =="
    fdisk -l /rootdisk/disk.img || true
  fi
  echo "== boot signature =="
  dd if=/rootdisk/disk.img bs=1 skip=510 count=2 2>/dev/null | od -An -tx1
'
