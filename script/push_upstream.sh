#!/usr/bin/env bash
set -euo pipefail

REMOTE="${1:-upstream}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repo" >&2
  exit 1
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "Remote '$REMOTE' not found. Add it with: git remote add $REMOTE <url>" >&2
  exit 2
fi

echo "Pushing all branches to '$REMOTE'..."
git push "$REMOTE" --all
echo "Pushing all tags to '$REMOTE'..."
git push "$REMOTE" --tags
echo "Done."

