# KilnCMS Unreleased — full release notes

The long-form entries behind the Unreleased section of
[CHANGELOG.md](../../CHANGELOG.md), as they were written when each change
merged. `CHANGELOG.md` carries the one-line summary of each; this file
carries the reasoning.

## Added

<a id="webhook-affected"></a>

- **Content webhooks carry `data.affected`: the published documents whose
  fired artifacts embed this one, so a consumer can invalidate those pages
  too instead of waiting out a TTL.** A formula page that lists a herb
  re-fires when the herb changes, so its delivered artifact changes too, but
  the `herb.updated` webhook named only the herb, and Verscienta.com's cache
  left the formula page to a 10-minute TTL. `KilnCMS.Firing.References.affected/1`
  reads the same reference edges the re-fire wave walks, tenant-scoped as
  the firing system actor, keeps the referrers that are currently published
  (the list is for invalidating pages a consumer serves), and names each as
  `type` (the public type name, as event names use it), `id`, `slug` and
  `locale`. `NotifyWebhooks` adds it to every full payload, `unpublished`
  included; tombstones stay identity only by contract. An empty list means
  nothing embeds the document; a failed lookup logs and answers `[]` rather
  than cost the delivery. `@kiln-cms/client` exports the `AffectedDocument`
  type and the Elixir client's `KilnClient.Webhook` documents the key.
  ([#1925](https://github.com/The-Verscienta/kiln_cms/issues/1925))

## Changed

<a id="subscription-retraction"></a>

- **A `<type>Changed` GraphQL subscription now tells anonymous subscribers
  when a published record is unpublished or archived, as `destroyed`.** A
  retraction is an `:update` to Ash, and ash_graphql resolves an update per
  subscriber through the policy-scoped read: once the record left
  `:published` the anonymous read answered not found, and the batcher
  suppresses not-found results rather than leak that a record exists, so the
  one event a public reader most needs never arrived. The GraphQL guide said
  as much and told readers to poll. `KilnCMS.CMS.Changes.NotifySubscribersWithdrawn`
  now sits beside `NotifyWebhooks event: "unpublished"` on `:unpublish`,
  `:unpublish_scheduled`, `:archive_scheduled` and `:archive` (the last only
  when the record was published) and publishes the same notification a real
  `:destroy` would, so the push arrives as `destroyed` with the id, the one
  arm of the union that needs no read. The contract, now in the guide:
  `destroyed` means the record left the published feed, whether unpublished,
  archived or deleted. A bearer-authed editor also receives the `updated`
  push for the same transition. Archiving a draft stays silent.
  ([#1925](https://github.com/The-Verscienta/kiln_cms/issues/1925))
