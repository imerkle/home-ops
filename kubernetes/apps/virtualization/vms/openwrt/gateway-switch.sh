#!/usr/bin/env bash

# Host-local route toggle for the router node.
# This does not replace the switch-level rollback needed for the rest of the LAN.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g., sudo ./gateway-switch.sh)"
  exit 1
fi

mode="${1:-isp}"

case "$mode" in
  isp)
    gateway="${2:-10.0.0.4}"
    ;;
  openwrt)
    gateway="${2:-}"
    if [ -z "${gateway}" ]; then
      echo "Usage: $0 openwrt <gateway-ip>"
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [isp|openwrt] [gateway-ip]"
    exit 1
    ;;
esac

echo "Switching the node default route to ${gateway} (${mode})..."
ip route replace default via "${gateway}"

echo "Current routing table:"
ip route
