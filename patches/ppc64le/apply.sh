#!/usr/bin/env bash
# Apply PPC64LE patches that could not be applied on the source-prep host
# (because they target third_party deps populated by gclient sync).
#
# Run this from the chromium src root AFTER gclient sync completes.
#
# Usage:
#   patches/ppc64le/apply.sh                 # apply deferred list
#   patches/ppc64le/apply.sh --all           # apply everything in series (for fresh trees)
#   patches/ppc64le/apply.sh --list FILE     # apply patches listed in FILE

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/deferred-needs-gclient-sync.txt"

case "${1:-}" in
  --all)   LIST="$HERE/series" ;;
  --list)  LIST="$2" ;;
  "")      ;;
  *)       echo "unknown arg: $1" >&2; exit 2 ;;
esac

fail=0
while IFS= read -r p; do
  [[ -z "$p" || "$p" == \#* ]] && continue
  # Strip inline comments after whitespace
  p="${p%%[[:space:]]*}"
  [[ -z "$p" ]] && continue
  if [[ ! -f "$HERE/$p" ]]; then
    echo "MISSING $p"; fail=$((fail+1)); continue
  fi
  echo "=== Applying $p"
  if ! patch -p1 --fuzz=2 -i "$HERE/$p"; then
    echo "FAIL   $p"; fail=$((fail+1))
  fi
done < "$LIST"

echo "Done. Failures: $fail"
exit "$fail"
