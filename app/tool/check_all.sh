#!/usr/bin/env bash
# Every invariant that is easy to break silently and impossible to see in a diff.
# Run in CI before the tests.
set -uo pipefail
cd "$(dirname "$0")"

fail=0
for check in check_domain_boundary.sh check_no_double.sh check_no_web_target.sh \
             check_strings_externalised.sh check_no_label_branching.sh \
             check_button_label_usage.sh; do
  ./"$check" || fail=1
done

if [ $fail -ne 0 ]; then
  echo
  echo "One or more invariants are broken. Each check's comment says why it exists."
  exit 1
fi
echo
echo "All invariants hold."
