#!/usr/bin/env bash
set -euo pipefail

REMOTE_URL="${1:-}"
if [ -z "$REMOTE_URL" ]; then
  echo "Usage: $0 <remote-url>" >&2
  exit 2
fi

BUNDLE="chatlog-all.bundle"
if [ ! -f "$BUNDLE" ]; then
  echo "Bundle '$BUNDLE' not found. Create it with: git bundle create $BUNDLE --all --tags" >&2
  exit 3
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Cloning bare from bundle..."
git clone --bare "$BUNDLE" "$tmpdir/repo.git"
cd "$tmpdir/repo.git"
echo "Pushing --mirror to $REMOTE_URL ..."
git push --mirror "$REMOTE_URL"
echo "Done."

