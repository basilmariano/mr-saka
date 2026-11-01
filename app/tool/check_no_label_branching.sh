#!/usr/bin/env bash
# FR-057: behaviour must never branch on display text. Categories, statuses and
# growth stages are identified by their constants; the label is a separate
# localised resource. A comparison against a quoted human string in the domain or
# data layer means translating that string would change what the app DOES.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r file; do
  # A string literal containing a space is prose, not an identifier or a key.
  hits=$(sed 's|//.*||' "$file" \
    | grep -nE "(==|!=)\s*['\"][A-Za-z]+ [A-Za-z ]+['\"]|\.contains\(\s*['\"][A-Za-z]+ " \
    | grep -v 'allow-label-branch:')
  if [ -n "$hits" ]; then
    echo "FAIL: behaviour branching on display text in $file"
    echo "$hits"
    fail=1
  fi
done < <(find lib/domain lib/data -name '*.dart' ! -name '*.g.dart')

[ $fail -eq 0 ] && echo "OK: no behaviour branches on display text"
exit $fail
