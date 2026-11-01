#!/usr/bin/env bash
# FR-056: all farmer-facing text lives in ARB files, so the phase-2 local language
# needs translation only — no screen changes. A string literal passed to Text() in
# the UI layer is a string a translator will never see.
#
# Checks Text('...') and Text("...") with literal content in lib/ui/. Interpolated
# and l10n-sourced strings are fine; so are symbols and units that are the same in
# any language.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r file; do
  hits=$(sed 's|//.*||' "$file" \
    | grep -nE "Text\(\s*['\"][^'\"\$]{2,}['\"]" \
    | grep -v 'allow-literal:')
  if [ -n "$hits" ]; then
    echo "FAIL: hardcoded farmer-facing text in $file"
    echo "$hits"
    fail=1
  fi
done < <(find lib/ui -name '*.dart')

[ $fail -eq 0 ] && echo "OK: farmer-facing text is externalised to ARB"
exit $fail
