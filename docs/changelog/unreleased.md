# KilnCMS Unreleased — full release notes

The long-form entries behind the Unreleased section of
[CHANGELOG.md](../../CHANGELOG.md), as they were written when each change
merged. `CHANGELOG.md` carries the one-line summary of each; this file
carries the reasoning.

<a id="image-backends"></a>

- **A plugin can contribute an image backend (`Kiln.ImageBackend`) — an
  external service such as Cloudflare Images that takes new image uploads and
  renders their variants and transforms from URLs.** A new plugin callback,
  `image_backends/0`, and an operator setting,
  `config :kiln_cms, :image_backend, Module`, which selects one; installing a
  plugin changes nothing until it is selected and reports itself configured.
  A new image upload bound for the operator's store goes to the backend when
  it accepts it — after metadata stripping, and never an image whose strip
  failed. Documents, video, audio and a site's own bucket (#1559) are
  untouched. The row records the backend's name in the new nullable
  `media_items.image_backend` column, and `KilnCMS.Storage` resolves it, so
  downloads, rotation, deletion and every other operation on that item reach
  the backend that holds it, whichever is selected later. The variant worker
  records the backend's URLs for the same labels, sizes and types the encoder
  would have written (`ImageProcessor.plan/4`), so the `variants` map reads
  the same to every client; `/media/:id/t/…` redirects to the backend after
  Kiln's own signing, allowlist and policy checks. A backend that can't render
  falls back to Kiln's encoder. The selected backend's delivery origin joins
  `img-src`. `mix kiln.plugins.doctor` checks the contract and the name, and
  System → Plugins says whether a backend is receiving uploads.
  `mix kiln.media.adopt_image_backend` hands the backend the rows imported by
  URL whose images it already holds (`key_for_url/1`), through a new
  system-only `adopt_into_image_backend` action on media items. The Cloudflare
  Images plugin itself ships separately.
  ([#1955](https://github.com/The-Verscienta/kiln_cms/issues/1955))

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

<a id="toolbar-keeps-editor-focus"></a>

- **Clicking a rich-text block's toolbar button keeps the caret in the text, so
  the first letters typed straight after Bold are no longer lost.** The block
  editor's toolbar let the browser move focus to the button on mousedown. The
  button's `chain().focus()` hands focus back to the editor only on the next
  animation frame, so keystrokes in that gap went to the button: click Bold,
  type "heavy" at once, and the block held a bold "avy". Each click also blurred
  the editor, which released the block's field lock and took it again. The
  toolbar now cancels mousedown, as the page editor's floating toolbar already
  did. The language select still opens.

<a id="collab-e2e"></a>

- **The browser suite now drives live co-editing: two peers type into one
  rich-text block and each sees the other's words and caret.** No spec
  exercised the CRDT path before (`mountCollab` in `assets/js/rich_text.js`,
  `assets/js/collab.js`): `:collab_prototype` was unset in `config/e2e.exs`,
  so every block mounted solo. During the TipTap 3 move (#1957) that hid a
  constructor throw that stopped every peer from syncing while all 33 editor
  specs passed. `e2e/tests/collab.spec.js` signs in as the admin and the
  editor in two contexts. A types, B sees it; A clicks away to release the
  field lock, B types, A sees it. It asserts B's remote caret renders in A's
  editor with a color and B's initials, that joining doubles no text, and
  that neither page throws. Reverting the #1957 guard fails it, and so does a
  joiner that seeds before the room's state arrives (`"AlphaAlphaAlpha"`).
  The flag stays off for the rest of the suite, as production pins it, so
  the other editor specs keep driving the solo editor and its reconnect
  re-send. The spec switches it on and back through a new e2e-only route,
  `POST /dev/e2e-collab` (`KilnCMSWeb.Plugs.E2ECollab`). The route is mounted
  beside `/dev/e2e-identity` in the compile-gated dev-tools scope, which
  `KilnCMS.Application` refuses in `:prod`.
