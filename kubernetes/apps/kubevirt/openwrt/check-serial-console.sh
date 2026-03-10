#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-kubevirt}"
vm_name="${2:-openwrt}"

launcher_pod="$(kubectl -n "$namespace" get pod -l kubevirt.io=virt-launcher,vm.kubevirt.io/name="$vm_name" -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$launcher_pod" ]]; then
  echo "No virt-launcher pod found for VM '$vm_name' in namespace '$namespace'." >&2
  exit 1
fi

serial_log="$(
  kubectl -n "$namespace" exec "$launcher_pod" -c compute -- \
    sh -lc 'find /var/run/kubevirt-private -name "virt-serial0-log" | head -n1'
)"

if [[ -z "$serial_log" ]]; then
  echo "No serial log file found in pod '$launcher_pod'." >&2
  exit 1
fi

log_size="$(
  kubectl -n "$namespace" exec "$launcher_pod" -c compute -- \
    sh -lc "wc -c < '$serial_log'"
)"

echo "virt-launcher pod: $launcher_pod"
echo "serial log: $serial_log"
echo "serial log bytes: $log_size"

if [[ "$log_size" == "0" ]]; then
  echo
  echo "The guest is not emitting output on ttyS0."
  echo "If 'virtctl console' hangs, recover with 'virtctl vnc -n $namespace $vm_name' and enable serial login inside OpenWrt."
  exit 2
fi

echo
echo "Recent serial output:"
kubectl -n "$namespace" exec "$launcher_pod" -c compute -- \
  sh -lc "tail -c 2000 '$serial_log'"
