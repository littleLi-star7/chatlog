#!/usr/bin/env bash
set -euo pipefail

# Prints the Windows host IP reachable from WSL2.
# Strategy: resolv.conf nameserver -> default route gateway.

get_host_ip() {
  local ip=""
  if [ -r /etc/resolv.conf ]; then
    ip=$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf || true)
  fi
  if [ -z "${ip}" ]; then
    ip=$(ip route | awk '/^default/ {print $3; exit}' || true)
  fi
  if [ -z "${ip}" ]; then
    echo "Unable to determine host IP" >&2
    return 1
  fi
  echo "$ip"
}

get_host_ip

