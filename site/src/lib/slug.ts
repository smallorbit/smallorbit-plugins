/**
 * Astro 5's legacy `type: 'content'` collections preserve the file extension
 * on `entry.id` (e.g. `flowkit.md`, not `flowkit`). Routes and links derived
 * from `entry.id` must strip it. The new content layer behaves differently;
 * if this project migrates, this helper becomes a no-op or is removed.
 */
export function stripExt(id: string): string {
  return id.replace(/\.(md|mdx)$/, '');
}
