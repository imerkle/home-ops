#!/usr/bin/env bash

# This script switches the default gateway back to the original ISP router IP: 10.0.0.4
# Run this if you need to bypass OpenWrt and use your ISP router directly for internet access.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g., sudo ./gateway-switch.sh)"
  exit 1
fi

echo "Switching default route to the ISP router (10.0.0.4)..."
ip route replace default via 10.0.0.4

echo "Current routing table:"
ip route
