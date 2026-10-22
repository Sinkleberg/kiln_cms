# KilnCMS Unreleased — full release notes

The long-form entries behind the Unreleased section of
[CHANGELOG.md](../../CHANGELOG.md), as they were written when each change
merged. `CHANGELOG.md` carries the one-line summary of each; this file
carries the reasoning.

## Added

<a id="fields-trims-the-fired-json-artifact-a-guide-to-kiln-in-a-native-app"></a>

- **`?fields=` trims the fired `json` artifact; a guide to Kiln in a native
  app.** `GET /api/content/:type/:slug?fields=title,slug,custom_fields.price`
  returns only the named top-level keys and custom fields, for clients on
  constrained networks that don't run GraphQL. `id` and `type` are always
  kept, as is `expanded` with `?expand=`; unknown names are ignored; at most
  50 names; `surface=json` only (`400 invalid_fields` otherwise); works with
  `?as_of=`. The `ETag` of a fieldset response is a digest of the filtered
  body, so it moves only when a kept value does — a republish that changed
  only `blocks` still `304`s a `?fields=title` revalidation — and every
  spelling of one fieldset shares it. `x-kiln-fields` echoes the canonical
  spelling (sorted, de-duplicated) so clients can share one CDN entry. A
  response without `fields` is unchanged, byte for byte and in its `ETag`.
  `/api/sync` still embeds the whole artifact.

  New page [native-apps.md](../native-apps.md): persisting the sync cursor,
  restarting with `initial=true` only on `invalid_cursor`, backoff and the
  per-IP rate limit, iOS/Android background-refresh limits, ETags for
  single-record refresh, `?fields=`, webhooks as the push path for apps with
  a backend, and typed models from `GET /api/schema`.

<a id="a-text-custom-field-can-also-be-delivered-as-plain-text"></a>

- **A `:text` custom field can also be delivered as plain text.** A new
  per-field toggle in the fields admin, "Also deliver as plain text"
  (`deliver_plain` on `FieldDefinition`, off by default), adds a
  `custom_fields_plain` map beside `custom_fields`: each flagged field's value
  with HTML tags removed, entities decoded and whitespace collapsed
  (`KilnCMS.PlainText.from_html/1`). It is for clients that cannot render the
  HTML fragments importers put into `:text` fields — a native app no longer
  needs a browser engine's HTML parser to show a paragraph. `custom_fields`
  itself is never rewritten.

  Where it appears: in the fired `:json` artifact, and so in
  `GET /api/content/:type/:slug` and every `/api/sync` item, whenever the
  type flags a field (absent otherwise, so other types' payloads are
  byte-identical); as the `custom_fields_plain` calculation on JSON:API
  (`fields[page]=…,custom_fields_plain`) and GraphQL (`customFieldsPlain`),
  served only on request like `inherited_fields`; and in the delivery schema
  (`GET /api/schema`, the `.d.ts`) as a closed object of nullable strings.
  Flipping the toggle re-fires the type's published documents. Not carried:
  the other fired surfaces (`:web`, `:llm`, `:json_ld` render text already),
  the public HTML page, feeds and CSV export, and a reference's link fields
  (the toggle is cleared on them, as on every non-`:text` type).

