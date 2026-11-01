#!/usr/bin/env bash
# plan.md Structure Decision: lib/domain/ must contain NO package:flutter import.
# That boundary is what keeps the SC-009 calculations testable under plain `dart test`,
# with no device and no widget framework. Enforced here rather than by convention.
set -uo pipefail
cd "$(dirname "$0")/.."
hits=$(grep -rn --include='*.dart' -E "^\s*import\s+'package:flutter/" lib/domain/ 2>/dev/null)
if [ -n "$hits" ]; then
  echo "FAIL: package:flutter imported inside lib/domain/"
  echo "$hits"
  exit 1
fi
echo "OK: lib/domain/ is free of package:flutter"
