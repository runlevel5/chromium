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
  # --forward (-N): if the patch looks already-applied or reversed, skip it
  #   cleanly instead of prompting. Critical for re-runs on partially applied
  #   state — otherwise patch stalls waiting for [y/n] and wedges the script.
  # --batch: never prompt, answer [no] to every question.
  # --no-backup-if-mismatch: don't leave .orig siblings on fuzz.
  # --reject-file=- / -r-: send rejects to stdout (visible) instead of .rej
  #   sitting next to the file (quieter error triage, still visible in log).
  if ! patch -p1 --fuzz=2 --forward --batch --no-backup-if-mismatch \
             -r /tmp/ppc64_reject.$$ \
             -i "$HERE/$p"; then
    echo "FAIL   $p"; fail=$((fail+1))
    [ -s /tmp/ppc64_reject.$$ ] && { echo "-- rejects --"; cat /tmp/ppc64_reject.$$; }
  fi
  rm -f /tmp/ppc64_reject.$$
done < "$LIST"

echo "Done. Failures: $fail"
exit "$fail"
