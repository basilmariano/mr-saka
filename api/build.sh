#!/usr/bin/env bash
# Bundles the four Lambda entrypoints into the zips Terraform uploads.
#
# mr-billing's apps produce a single ../package.zip from their own build; Saka's API
# fans out to four handlers, so this produces one zip each under api/build/, which is
# what api/terraform/lambda.tf reads via src_path.
#
# Run before `terraform plan`/`apply`: filebase64sha256 reads these files at plan
# time, so a missing zip fails the plan rather than deploying something stale.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/build"

[ -x "$here/node_modules/.bin/esbuild" ] || {
  echo "esbuild not found. Run: (cd api && npm install)" >&2
  exit 1
}

rm -rf "$out"
mkdir -p "$out"

for fn in mutations snapshot account reference; do
  mkdir -p "$out/$fn"

  # --external:@aws-sdk/* keeps the AWS SDK out of the bundle: the Node 22 runtime
  # already ships v3, so bundling it would add megabytes and pin a copy that stops
  # getting the runtime's security updates.
  "$here/node_modules/.bin/esbuild" "$here/src/lambda/$fn.ts" \
    --bundle \
    --platform=node \
    --target=node22 \
    --format=esm \
    --external:'@aws-sdk/*' \
    --outfile="$out/$fn/index.mjs" \
    --log-level=warning

  # .mjs so the Node runtime loads it as ESM regardless of any package.json.
  (cd "$out/$fn" && zip -q -r "../$fn.zip" .)
  printf '  %-10s %s\n' "$fn" "$(du -h "$out/$fn.zip" | cut -f1)"
done

echo "bundled 4 functions into $out"
