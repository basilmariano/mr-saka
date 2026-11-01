#!/usr/bin/env bash
# research.md R1/R5: Dart's int is 64-bit on Android and iOS but a JavaScript double
# on Flutter web. Compiling for web would silently turn every peso amount into a float
# and break SC-009 with no error anywhere. This guard makes that failure loud.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
if [ -d web ]; then echo "FAIL: a web/ target directory exists"; fail=1; fi
hits=$(grep -rn --include='*.dart' -E "import\s+'dart:(html|js|js_util|js_interop)'" lib/ 2>/dev/null)
if [ -n "$hits" ]; then echo "FAIL: web-only dart: imports found"; echo "$hits"; fail=1; fi
[ $fail -eq 0 ] && echo "OK: no web target, no web-only imports"
exit $fail
