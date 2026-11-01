#!/usr/bin/env bash
# SC-009 commits that every figure matches the farmer's own calculator. Binary floating
# point cannot represent 0.1 exactly, so repeated addition of peso amounts drifts.
# No double may appear in DOMAIN CODE. Comments may discuss it freely, so comments are
# stripped before the check - otherwise the rule cannot be documented where it applies.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
while IFS= read -r file; do
  # strip // and /// comments, then look for a double/Float type in real code
  hits=$(sed 's|//.*||' "$file" | grep -nE '(^|[^A-Za-z0-9_])(double|Float)([^A-Za-z0-9_]|$)' | grep -v 'allow-double:')
  if [ -n "$hits" ]; then
    echo "FAIL: floating point in $file"
    echo "$hits"
    fail=1
  fi
done < <(find lib/domain -name '*.dart')
[ $fail -eq 0 ] && echo "OK: lib/domain/ uses no floating point"
exit $fail
