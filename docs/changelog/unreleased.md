# KilnCMS Unreleased — full release notes

The long-form entries behind the Unreleased section of
[CHANGELOG.md](../../CHANGELOG.md), as they were written when each change
merged. `CHANGELOG.md` carries the one-line summary of each; this file
carries the reasoning.

<a id="prosemirror-view-paste-xss"></a>

- **prosemirror-view 1.42.6 for GHSA-c8x8-7fp4-3x9w: pasting HTML into the
  rich-text editor can no longer run script.** The advisory (HIGH) is an XSS
  in prosemirror-view's paste handling, which the TipTap editor bundled into
  `app.js` uses. A non-breaking `npm audit fix` in `assets/` also takes
  markdown-it 14.3.2 and linkify-it 5.0.2 (GHSA-253c-mchw-3w2r, quadratic
  parsing with `linkify: true`) and TipTap 2.27.3. TipTap's own
  `mergeAttributes()` advisory (GHSA-cp6q-959q-f8rh, MODERATE) is fixed only
  in TipTap 3 and stays open until the editor moves to v3. Outside the shipped
  bundle, `clients/js` moves to vitest 5 (critical and high advisories in its
  test-only tinypool, vite and esbuild) and `examples/astro-blog` to Astro 7;
  both report no advisories now.
