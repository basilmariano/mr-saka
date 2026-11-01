#!/usr/bin/env bash
# ButtonLabel wraps its text in a Flexible, so it is only valid as the direct
# child of an FButton (whose Content is a Row). Inside an Expanded or another
# Flexible it writes competing parent data to the same RenderObject and the frame
# throws; inside FBadge or FTile there is no Flex at all.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r file; do
  hits=$(grep -nB2 'ButtonLabel(' "$file" \
    | grep -E 'Expanded\(|Flexible\(|FBadge\(|FTile\(|FAlert\(' || true)
  if [ -n "$hits" ]; then
    echo "FAIL: ButtonLabel inside a non-FButton or flex parent in $file"
    echo "$hits"
    fail=1
  fi
done < <(grep -rl 'ButtonLabel(' lib/ui --include='*.dart')

[ $fail -eq 0 ] && echo "OK: ButtonLabel is only used as an FButton child"
exit $fail
