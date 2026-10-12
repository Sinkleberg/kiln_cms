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

<a id="tiptap-3"></a>

- **The rich-text editor moves to TipTap 3 for GHSA-cp6q-959q-f8rh, and keeps
  underlines it used to drop; a co-editing tab still on the old bundle edits
  solo until it reloads.** The advisory (MODERATE) is in TipTap's
  `mergeAttributes()`: an attribute object with an own `__proto__` key turns
  into inherited DOM attributes, a path to script in the editor. It is fixed
  only in TipTap 3. StarterKit 3 bundles Link, Underline, ListKeymap and
  TrailingNode. Kiln keeps its own `safeHref`-gated Link and turns
  StarterKit's off, and turns TrailingNode off so a closing table or code
  block does not save an empty paragraph after it. Underline stays on: the
  server already stored and rendered underline marks, but the old editor had
  no such mark and stripped one from API-authored prose the next time the
  block was edited. Ctrl/⌘U now applies it. The shared Yjs schema gains that
  mark, so the collab schema version goes from 2 to 3, and a tab open across
  the deploy is refused from the room ("stale bundle") instead of stripping
  its peers' underlines. It keeps editing solo with autosave. Under the hood:
  `@tiptap/extension-collaboration-cursor` becomes `-caret`, the table
  row/cell/header packages fold into `@tiptap/extension-table`,
  `y-prosemirror` gives way to `@tiptap/y-tiptap`, and `setContent` takes an
  options object (v3 emits an update by default, so the reconnect reload now
  passes `emitUpdate: false` explicitly).
