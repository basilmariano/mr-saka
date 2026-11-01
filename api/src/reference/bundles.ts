/**
 * Published agronomic bundles. research.md R9, R10.
 *
 * Immutable and monotonically versioned, so the device's state is unambiguous: it
 * has bundle N or it does not. That keeps the client-side merge a simple
 * replace-by-provenance rather than a field-level diff.
 */
export interface PublishedBundle {
  version: number;
  publishedAt: string;
  isPlaceholder: boolean;
  varieties: unknown[];
  templates: unknown[];
}

/**
 * The bundles this deployment serves.
 *
 * Feature 002 (the CRM) replaces this with bundles authored by PhilRice and the
 * Bureau of Plant Industry. Until then the app ships its own seed bundle, and this
 * endpoint exists so corrected guidance can reach phones that never update the app
 * (FR-026b).
 */
const BUNDLES: PublishedBundle[] = [];

export function currentBundle(): PublishedBundle | undefined {
  if (BUNDLES.length === 0) return undefined;
  return BUNDLES.reduce((a, b) => (b.version > a.version ? b : a));
}

export function bundleNewerThan(version: number): PublishedBundle | undefined {
  const current = currentBundle();
  if (!current || current.version <= version) return undefined;
  return current;
}
