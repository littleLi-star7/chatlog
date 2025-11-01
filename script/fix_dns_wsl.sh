#!/usr/bin/env bash
set -euo pipefail

# Fix DNS in WSL2 by disabling auto resolv.conf and writing static resolvers.
# Usage:
#   bash script/fix_dns_wsl.sh            # show current status + what would change (dry-run)
#   sudo bash script/fix_dns_wsl.sh apply # apply changes (requires sudo), then run `wsl --shutdown` in Windows
#   sudo bash script/fix_dns_wsl.sh revert# revert to WSL-managed resolv.conf

NAMESERVERS=("1.1.1.1" "8.8.8.8")
RESOLV_OPTS="options timeout:1 attempts:2 rotate edns0"

have() { command -v "$1" >/dev/null 2>&1; }

status() {
  echo "== /etc/wsl.conf =="
  if [ -f /etc/wsl.conf ]; then
    sed -n '1,200p' /etc/wsl.conf
  else
    echo "(missing)"
  fi
  echo
  echo "== /etc/resolv.conf =="
  ls -l /etc/resolv.conf || true
  sed -n '1,120p' /etc/resolv.conf || true
  echo
  echo "== DNS resolution check =="
  for d in example.com github.com gitcode.com go.dev; do
    printf "%-16s" "$d"; getent hosts "$d" | awk '{print $1}' | paste -sd, - || echo "(no DNS)"; done
}

ensure_wsl_conf() {
  local tmp
  tmp=$(mktemp)
  if [ -f /etc/wsl.conf ]; then
    cp /etc/wsl.conf "$tmp"
    if ! awk '/^\[network\]/{f=1} f && /generateResolvConf/{exit 0} END{exit 1}' "$tmp"; then
      printf "\n[network]\n" >> "$tmp"
      echo "generateResolvConf = false" >> "$tmp"
    else
      # normalize to false
      sed -i 's/^\(\s*generateResolvConf\s*=\s*\).*/\1false/' "$tmp"
    fi
  else
    cat > "$tmp" <<EOF
[network]
generateResolvConf = false
EOF
  fi
  install -m 0644 "$tmp" /etc/wsl.conf
  rm -f "$tmp"
}

write_resolv_conf() {
  # Replace symlink with regular file and write static resolvers
  if [ -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf
  else
    cp -a /etc/resolv.conf /etc/resolv.conf.bak.$(date +%s) || true
  fi
  {
    echo "# Static resolv.conf managed by chatlog script"
    for ns in "${NAMESERVERS[@]}"; do echo "nameserver ${ns}"; done
    echo "$RESOLV_OPTS"
  } > /etc/resolv.conf
  chmod 0644 /etc/resolv.conf
}

apply_changes() {
  ensure_wsl_conf
  write_resolv_conf
  echo "Applied. To finalize, run in Windows PowerShell: wsl --shutdown"
}

revert_changes() {
  # Re-enable auto resolv.conf and remove static file
  local tmp
  tmp=$(mktemp)
  if [ -f /etc/wsl.conf ]; then
    cp /etc/wsl.conf "$tmp"
    # Remove [network] block or set generateResolvConf=true
    if awk '/^\[network\]/{f=1} f && /generateResolvConf/{exit 0} END{exit 1}' "$tmp"; then
      sed -i 's/^\(\s*generateResolvConf\s*=\s*\).*/\1true/' "$tmp"
    else
      printf "\n[network]\n" >> "$tmp"
      echo "generateResolvConf = true" >> "$tmp"
    fi
  else
    cat > "$tmp" <<EOF
[network]
generateResolvConf = true
EOF
  fi
  install -m 0644 "$tmp" /etc/wsl.conf
  rm -f "$tmp"
  echo "Reverted. Then run in Windows PowerShell: wsl --shutdown"
}

case "${1:-dry-run}" in
  apply) apply_changes;;
  revert) revert_changes;;
  *) echo "(dry-run) Showing current status"; status; echo; echo "Run: sudo bash $0 apply  # to apply changes";;
esac

