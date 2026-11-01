# Agronomic reference data

`bundle-v1.json` currently ships with **`"isPlaceholder": true`** and every maturity
and per-hectare rate set to a stand-in value.

## Why it is empty rather than plausible

FR-026 requires the app to tell the farmer that recommendations are general guidance.
That statement is only honest if the figures are genuine published guidance. Shipping
invented-but-plausible rates would be worse than shipping none: a farmer would apply
them, and the app would have given agronomic advice nobody wrote.

Variety names, growth stages and fertilizer product names come from the feature
specification and are real. **The numbers do not.**

## What must happen before a real farmer uses this

1. Transcribe maturity days per variety from PhilRice published varietal guides.
2. Transcribe per-hectare rates per crop and planting method from PhilRice / Bureau of
   Plant Industry fertilizer guidance.
3. Record the actual publication and date in each `sourceAttribution` (FR-026a).
4. Set `"isPlaceholder": false`.

`ReferenceBundle.isPlaceholder` exists so the app can refuse to present unverified
figures as guidance, rather than relying on someone remembering this file.

Tracked as task T037 (seed) and T151 (replace before release). In the longer term this
data comes from the feature 002 CRM, authored by PhilRice and BPI directly.
