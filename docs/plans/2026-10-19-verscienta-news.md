# Plan: Verscienta News on Kiln

Written 2026-10-19 against Kiln v1.5.0, revised the same day with the owner's
answers to the open questions. Like [path-forward.md](../path-forward.md),
this page is a plan, not a status board: issues win when the two disagree.

## Summary

Verscienta News is a **holistic-health news site with two kinds of content**:
articles written in-house, and curated items from licensed sources. A person
reviews every item before it goes public. In Kiln's own roadmap it is also the
**pilot for 3.0 "Live delivery"**: the site where a correction lands on open
pages while you watch, and every change has its trail.

It builds in this order:

1. **Trust-first launch** (Phases 0 and 1): Slice 1 from the news repo
   (licensed curation, human review, attribution, disclaimer, claim status)
   plus in-house articles. Reader pages are Kiln's own rendered pages in
   the Codex design.
2. **Right, provably** (Phase 2): corrections, retractions, claim checking,
   provenance, and herb references to Verscienta.com that stay current when
   the herb entry changes.
3. **Live, on SvelteKit** (Phase 3): a SvelteKit reader takes over the same
   URLs, wired to Kiln's change feed: breaking bar, live blogs, open pages
   that update themselves.
4. **Audience** (Phase 4): reader accounts owned by the SvelteKit front end,
   topic follows, newsletter, comments. No monetisation until after this.

## Decisions taken 2026-10-19

| Question | Answer |
|---|---|
| Design | **The Codex v6** (`docs/design/the-codex-v6.html`, `codex-tokens.css` in the news repo). The scaffold's earth palette is retired |
| Content | **In-house articles and curated licensed items**, both reviewed by a person. In-house articles may **reference Verscienta.com herb and formula records** |
| Readers | **The front end owns reader identity.** Kiln accounts stay staff-only |
| Reader front end | **Kiln's rendered pages first, SvelteKit from Phase 3** |
| Hosting | **News gets its own Kiln install**, separate from Verscienta.com |
| Monetisation | **None at launch.** No ads, no paywall |

## Where it stands

Three things exist, and only one of them is pushed.

| Piece | Where | State |
|---|---|---|
| Scaffold | `The-Verscienta/verscienta-news` on GitHub, one commit (2026-10-03) | Kiln **v1.0.0** submodule; overlay `projects/verscienta_news/` with `Article`, one block and a plugin; stubs for ingestion, AI, gamification and social; a SvelteKit 4 front end |
| **Slice 1 re-scope** | `~/Github/verscienta-news/verscienta-news`, **uncommitted, not pushed** | `docs/slice-1.md`, `source-rights.md`, `moderation.md`, `plan-critique.md`, a reworked `architecture.md`, the Codex files, and edits to the stubs (Oban + Req poller, no Broadway, no auto-publish) |
| Older app | `The-Verscienta/news-verscienta`, 973 commits, last touched 2026-06-18 | A standalone Phoenix LiveView aggregator (Meilisearch, Redis, gamification, LiveKit). Historical: kept for its decisions, audits and runbooks, not built on |

Slice 1's plan critique (`docs/plan-critique.md`, in the local checkout)
reached the same verdict as this plan: put trust ahead of engagement, keep a
single delivery path, write down source rights, and draw an explicit cut line.
This plan adopts Slice 1 wholesale as the core of Phase 1 and adds in-house
writing, Kiln 1.1–1.5 features and the later phases around it.

## Decisions

Numbered `N` so they don't collide with Kiln's `D1`–`D23`.

### N1. Kiln is an upstream dependency, consumed through the overlay contract only

Pin Kiln to a **release tag**, never `main`. The news code is a
`kiln_plugin`-based package listed in `config/project_deps.exs` (#1967),
activated by `config/project.exs`. It touches only covered surfaces in
[overlay-contract.md](../overlay-contract.md#covered-surfaces): the
`KilnCMS.CMS.Content` options, `Kiln.Block` and its renderer, `Kiln.Plugin`
(including `public_routes`), the workflow action names and the HTTP API.
Nothing under `KilnCMSWeb.*`.

**Why:** the site has to ride every wedge minor from 1.6 to 3.0 without code
changes, because it pilots several of them.

**CI on the news repo:**

- With the overlay activated: `mix ash.codegen --check` and `mix kiln.plugins.doctor`.
- Against a migrated database: `mix kiln.search.check`.
- From the pinned checkout: `mix kiln.update --check --exit-code`.
- Slice 1's own tests (allowlist, licence truncation, dedupe).

### N2. Reader front end: Kiln pages and plugin routes now, SvelteKit in Phase 3

**Phases 1 and 2.** There is one delivery path, and Kiln serves it.

- **Articles** are Kiln's rendered pages at `/<section>/<slug>`.
- **Home, section fronts, topic pages and the breaking bar** are the overlay's
  own pages, mounted through `Kiln.Plugin.public_routes` (covered). They read
  published content through the overlay's code interfaces. Kiln's stock
  front page is a fixed design that can't show a news front.
- **Codex styling** goes in Kiln's site **custom CSS** (code injection),
  targeting the covered `public-*` hook classes. Articles use the Codex's
  light reading canvas (`--read-bg`), and fronts use its dark canvas.

**Phase 3.** A SvelteKit (Svelte 5) reader takes over the same URLs. It reads
only Kiln's published-only surfaces through `@kiln-cms/client`, using a
delivery key minted on a `:viewer` account and types generated by
`kiln-types`. The plugin public routes are then retired, so there is still
one delivery path at a time.

**Why this order:** launch doesn't wait on a second app. SvelteKit arrives
when it has work only it can do: the live change feed (Kiln 2.3 pilots
`kiln.subscribe()` here) and reader identity (N9).

**Constraint to design around:** an overlay can't add markup to Kiln's article
template. Attribution, the claim badge and correction notes are therefore
**blocks** with `:web` renderers. The overlay's `Article` keeps them in sync
through an Ash change; the editor never places them by hand. The disclaimer
goes in the site footer, via code injection footer HTML, so it appears on
every delivery page. If that proves brittle, ask upstream for a covered
"document meta slot" (U9).

### N3. Content model

All types are `use KilnCMS.CMS.Content` resources in the overlay.

| Type | Purpose | Notes |
|---|---|---|
| `Article` | Both in-house and curated items | `schema_org_type: "NewsArticle"`. Fields: `origin` (`in_house` or `curated`), `kind` (news, explainer, analysis, opinion), `dek`, lead image, `claim_status` (`unreviewed`, `flagged`, `cleared`; `verified` waits for Verified Expert). Curated items add Slice 1's fields: `source_url` (unique), `source_license` (`full_text`, `excerpt_link`, `link_only`), `attribution_text`, `robots_policy` |
| `Author` | Public byline and profile | Kiln's `author` is a console `User`, which is not public on JSON:API by design. Bylines are their own published type, many-to-many with `Article` (relationships, Kiln 1.5), optionally linked to a `User` |
| `LiveStory` + `LiveUpdate` | Live blog (Phase 3) | Each update is its own published record related to its story, so each one gets its own firing, feed event and history entry |
| Sections | Nutrition, Herbalism, Mindfulness, Movement, Functional Medicine, TCM, Ayurveda, Environment | Kiln's (flat) categories, not a free-text field. **Watch #1595**: Kiln 2.0 merges categories and tags |
| Tags | Topics, conditions, herbs | Kiln tags; taxonomy webhooks keep topic pages fresh |

**Blocks** are `Kiln.Block`, versioned with `migrate` from day one:

| Block | Purpose |
|---|---|
| `sources` | Citations: title, publisher, URL, DOI, date accessed, evidence level |
| `source_attribution` | Curated items: attribution text, source link, licence |
| `claim_badge` | Kept in sync from `claim_status` |
| `correction_note` | The reader-facing half of a correction (N4) |
| `herb_ref` | A Verscienta.com herb or formula card (N10) |
| `key_points` | Summary bullets |
| `pull_quote` | Pulled quotation |
| `wellness_callout` | Already exists |
| `embed` | Through Kiln's curated provider list |

**Codex category colours.** The Codex palette was drawn for general news:
world, politics, tech, culture, sport, money, violet. Map each wellness
section to one of the seven colours. Always pair the colour with the section
name ("pair every category color with a word"). Eight sections and seven
colours means one section shares or goes neutral; decide that in Phase 1.

### N4. Corrections, retractions and takedowns

- **Correction:** an edit made in Kiln's working copy (the public version is
  untouched until approval), plus a `correction_note` block and a visible
  "Updated" stamp. Kiln history records the diff and who approved it.
- **Retraction:** `:unpublish` or `:archive`, which Kiln 1.4 guarantees reaches
  every webhook endpoint. The page shows a retraction notice with HTTP 410 and
  the reason, never a bare 404.
- **Takedown** (curated items, from `source-rights.md`): archive the item and
  blocklist its `source_url`. The poller checks the blocklist before it
  inserts anything.
- **History link:** every article links to its history, backed by `?as_of=`
  and the provenance verdict from `/api/provenance/:type/:slug/verify`.
  Provenance is shipped but off by default; it is on in the `publishing`
  preset, and on by default from Kiln 1.7.

### N5. Health claims: human review, then Kiln's claim checking

- **Slice 1:** the approval checklist in `moderation.md`. A `flagged` item
  can't be approved until a moderator clears it.
- **Phase 2:** Kiln's claim checking (`docs/compliance.md`), configured with a
  wellness vocabulary. Examples: "cures", "treats", "prevents", dosing
  language, drug names near herb names. A hit with an empty `sources` block
  refuses the publish.
- **Later:** Kiln 3.3 turns this into an approval policy, such as "health
  claims need a second approver".

### N6. Search is Kiln's Postgres search

No Meilisearch and no pgvector search. Kiln's published search plus section
and tag filters is the whole of search. Revisit only with a measured miss.

### N7. Freshness: webhooks and CDN purges now, the change feed in Phase 3

- **Phases 1 and 2:** Kiln's tag-based CDN purge (`KILN_CDN_PURGE_URL`)
  covers articles. The plugin's front pages purge on the Kiln webhook, for the
  record and its `data.affected` referrers.
- **Phase 3:** the SvelteKit reader subscribes to Kiln's change feed (Kiln
  2.2/2.3: `/api/feed` over SSE, or the `feed:<site>` channel). Webhooks stay
  for CDN purges.
- **Not GraphQL subscriptions:** `/ws/gql` is experimental and may be
  deprecated in favour of the feed.

### N8. Curated ingestion: Slice 1 as written

Slice 1's rules carry over unchanged:

- An Oban cron job (`*/15 * * * *`) fetches feeds with Req. No Broadway.
- `VerscientaNews.Ingestion.Allowlist` is the only registry. Each entry
  carries `url`, `license`, `attribution_text`, `robots`, `robots_notes`,
  `owner_contact` and `takedown_sla`.
- `Poller.apply_license/1` truncates or drops the body **before** it is
  stored.
- Every item lands `in_review`. No score ever publishes anything.
- Ollama is optional and advisory (Compose profile `ml`). If it is down,
  drafts still wait in review.

One change from Slice 1: **outbound fetches go through `KilnCMS.SafeFetch`**
(Kiln ADR 0008), which pins the resolved address against SSRF. That module
isn't a covered surface yet, so either ask upstream to cover it (U10) or copy
its guarantees into the overlay with a test.

### N9. Readers belong to the front end, from Phase 4

Kiln accounts stay staff-only (admin, editor, writer). In Phase 4 the
SvelteKit app owns reader identity: passkeys or magic links, kept in its own
store, never a Kiln `User`. Reader-generated data (follows, comments) lives on
the front end's side too.

**Why:** Kiln's memberships are frozen upstream, and Kiln treats reader
comments as an explicit non-goal. The cost is a second datastore. Decide in
Phase 4 whether that is a small Postgres schema owned by the SvelteKit server
or a hosted auth service.

### N10. Herb references to Verscienta.com stay current

The installs are separate, so a reference is to a Verscienta.com record by
`type` and `slug`, never a copy of its content.

- **Rendering:** a `herb_ref` block shows a card (name, key safety note, link)
  built from Verscienta.com's published API at fire time.
- **Freshness:** the news install subscribes to Verscienta.com's signed
  webhooks for `herb` and `formula`. On a change, it finds the news articles
  whose `herb_ref` names that slug and re-fires them. A herb safety correction
  then reaches every news article that mentions the herb. This is Kiln's demo
  line 2 running across two installs.
- **Gap:** "re-fire this record" isn't a covered surface for an overlay
  (`mix kiln.refire_all` is an operator task). Ask upstream (U11).

### N11. Hosting: its own install

The news site gets its own Kiln container and Postgres, deployed from Kiln's
`deploy/presets/publishing.env` on Coolify (the news repo's
`deploy-coolify.md`). Pilot work for Kiln 2.x and 3.x then can't disturb
Verscienta.com's clinical content, and each site upgrades on its own schedule.
Staging mirrors production.

## Phases

Each phase has one exit test. Durations assume one developer and Kiln's
two-to-four-week minor cadence.

### Phase 0: Reset (about 1 week)

- **Commit and push the local Slice 1 work** first, so nothing else lands on
  top of an unsaved re-scope.
- Bump the submodule from v1.0.0 to `v1.5.0` and work through the upgrade
  notes for 1.1 to 1.5.
- Move the overlay to the plugin-as-dependency layout.
- Delete the cut stubs (gamification, social, recommendation, Broadway
  pipeline).
- Trim `config/project.exs` to the domains the site uses.
- Postgres-only Compose, plus the optional `ml` profile.
- Retire the earth palette and bring `codex-tokens.css` in as the single
  token source.
- CI per N1.
- Stand up a Coolify staging site.

**Exit:** staging boots from a clean clone, CI is green, and an editor can
publish an `Article` that renders at `/<section>/<slug>`.

### Phase 1: Trust-first launch (4 to 6 weeks)

**Curated items (Slice 1):** pass every Slice 1 exit criterion in
`docs/slice-1.md`:

- The allowlist is the only registry.
- Licence truncation happens before the body is stored.
- Re-polling the same URL creates no duplicate.
- Items stay `in_review` while Ollama is down.
- Takedown and blocklist work.
- Kiln search returns the seeded items.
- None of the cut modules are in `ash_domains`.

**In-house articles:**

- **Content types:** `Author`, sections, and the `sources`, `key_points` and
  `pull_quote` blocks.
- **Roles:** writer (can submit, can't publish), editor, admin. Check Kiln's
  granular RBAC before adding anything of your own.
- **Workflow:**
  - `scheduled_at` for embargoed publishes, `unpublish_at` for pieces that
    expire.
  - `/editor/inbox` and the review work queues as the editors' desk.
  - `/editor/calendar` for planning.
  - Content releases for packages that must go live together.
  - Editorial consent records for image licences.

**Reader pages (N2):**

- **Article page:**
  - Codex custom CSS on the light reading canvas.
  - The `source_attribution` and `claim_badge` blocks.
  - The disclaimer "Not medical advice — for information only. Consult a
    qualified professional." in the footer.
- **Plugin public routes:** home, section fronts, author pages, topic pages,
  `/corrections`, `/about`, and a standards page. Built with Codex article
  cards: kicker, headline, a little metadata, the category colour and its
  word.
- **SEO:**
  - `NewsArticle` JSON-LD.
  - Kiln's `/sitemap.xml`.
  - Atom and JSON Feed per section and tag.
  - A Google News sitemap (U3).
- **Images:** through Kiln's image transforms endpoint.
- **Budgets:** WCAG AA, which the Codex's contrast ratios already target.
  Compact mode and a reduced-motion path for every component, per the Codex.
  LCP under 2.5 s on 4G.

**Exit:** all Slice 1 exit criteria pass on staging. Twenty curated items and
ten in-house articles by two authors are published through review. An edit
reaches the article, its section front and its author page within the CDN
purge time, and that time is measured.

### Phase 2: Right, provably (3 to 4 weeks; tracks Kiln 1.6 and 1.7)

- Correction, retraction and takedown pages and notices, per N4.
- Claim checking configured as described in N5.
- Provenance signing turned on, with a history link and a "verified" mark on
  every article. The "what readers saw" timeline arrives with Kiln 1.6.
- `herb_ref` and cross-install freshness, per N10.
- First freshness number: Kiln 1.5's propagation records
  (`mix kiln.propagation`) for this site's endpoints.

**Exit:**

- Path-forward demo lines 1 and 4 pass on this site.
- An edit to a herb's safety note on Verscienta.com staging appears in a news
  article that references it, within a measured time.

### Phase 3: Live, on SvelteKit (tracks Kiln 2.1 to 2.5)

1. **SvelteKit parity.**
   - Svelte 5, `adapter-node` behind the CDN, `@kiln-cms/client`,
     `kiln-types`, and the Codex tokens.
   - Every Phase 1 route at the same URL, with a Portable Text renderer for
     every block.
   - Then retire the plugin public routes.
2. **Live.**
   - Subscribe to the change feed (N7).
   - Open article pages refresh in place on `updated`, and swap to the
     retraction notice on `withdrawn`.
   - The Codex breaking bar, driven by a pinned `LiveStory`.
   - `LiveStory` pages stream new `LiveUpdate`s in at the top, with "N new
     updates" when the reader has scrolled away.
3. **Measure.**
   - Publish-to-open-page p95.
   - Unpublish-to-last-open-page p95.

**Exit:**

- Demo lines 2 and 3 pass in production and are recorded.
- Both p95 numbers are on Kiln's benchmarks page.

### Phase 4: Audience (only after Phase 3 is live)

These come in value order, and each needs its own go-ahead first.

1. **Newsletter:** a daily digest per section. Use Kiln's newsletter (frozen
   upstream, but it works) with email-only signup, so it needs no account.
2. **Reader accounts and topic follows,** per N9.
3. **Comments:** owned by the front end and pre-moderated on health topics.
   The Codex already has a comment-thread pattern.
4. **Verified Expert:** a credential review that adds `claim_status:
   verified`.
5. **Recommendations:** "more in this section" and Kiln's `/related` first.
   Anything learned from behaviour needs a cold-start spec and usage data.

Monetisation stays off the table until a decision after Phase 4.

## Cut

| Item | Why |
|---|---|
| Auto-publishing on a model score | Slice 1 removed it already. A health claim never goes public without a person approving it |
| Broadway | An Oban cron job plus Req is the right shape for a 15-minute poll |
| Meilisearch, pgvector search, Redis, Dragonfly | N6, Kiln D1/D2 |
| LiveKit rooms | No demo line, and a large operational surface |
| Gamification | Points for dwell time pay people to linger, and leaderboards on health advice reward volume |
| `/write`, a second TipTap editor | Editors use Kiln's console |
| The earth palette | Replaced by the Codex |

## Upstream work this site needs from Kiln

| # | Need | When | Notes |
|---|---|---|---|
| U1 | Publish `@kiln-cms/client` to npm | Phase 3 (a git dependency until then) | Its release workflow already exists |
| U2 | A documented recipe for public author profiles | Phase 1 | `User` stays private |
| U3 | Google News sitemap (`news:` namespace, items from the last 48 hours) | Phase 1 | Small; `SitemapController` exists |
| U4 | Kiln 1.6 and 1.7 | Phase 2 | #1928, #1929 |
| U5 | Kiln 2.1 to 2.5 | Phase 3 | This site is the pilot |
| U6 | Firing and feed cost when a live blog posts an update every few seconds | Phase 3 | A benchmark |
| U7 | Add `LiveBlogPosting` to the schema.org allowlist | Phase 3 | One line plus a test |
| U9 | A covered "document meta slot" on article pages, if the block approach (N2) proves brittle | Phase 1, if needed | |
| U10 | Make `KilnCMS.SafeFetch` a covered surface for plugins | Phase 1 | N8 |
| U11 | A covered way for an overlay to re-fire a record | Phase 2 | N10 |

## Risks

| Risk | What we do |
|---|---|
| Phase 3 waits on Kiln 2.x, which waits on the 2.0 gate | Phases 1 and 2 are complete without the feed; the feed is Phase 3 only |
| Codex styling through custom CSS on Kiln's templates falls short of the design | Fronts are the plugin's own pages; only the article body depends on `public-*` hooks. If the article page can't reach the Codex, pull the SvelteKit reader forward |
| Licence or robots mistakes on curated items | Slice 1's allowlist, truncation before storage, the takedown SLA, and its tests |
| #1595 (Kiln 2.0) changes how sections are stored | Sections ride on categories with slug redirects; rehearse the 2.0 upgrade on staging first |
| Scope creeps back toward the old app's breadth | One exit test per phase; nothing from Phase 4 starts before Phase 3's exit |
| Verscienta.com's API or webhooks change under `herb_ref` | Both sites run Kiln under the same webhook contract; cards fall back to a plain link |
| Health-content liability | N4 and N5, the standards page, and the disclaimer on every page |

## Still open

1. **Which sources go on the allowlist first?** Slice 1's single row is a
   placeholder. No real publisher is polled until each row has been checked
   for licence and robots.
2. **Verscienta.com API access for `herb_ref`:** decide whether it uses a
   `:viewer` delivery key, which webhook endpoint it registers, and who owns
   that endpoint.
3. **Section colours:** how eight sections map onto the Codex's seven colours.
4. **Reader identity store** in Phase 4: self-hosted or a service.

## First PRs

1. verscienta-news: commit the local Slice 1 docs, the Codex files and the
   stub edits as they are.
2. verscienta-news: bump Kiln to v1.5.0, plugin-as-dependency layout, delete
   the cut stubs, CI per N1.
3. verscienta-news: allowlist, poller, `Article` curated fields, and the
   Slice 1 tests.
4. verscienta-news: `Author`, sections, blocks, and the plugin public routes
   with the Codex styling.
5. kiln_cms: U3 (news sitemap), U10 (SafeFetch for plugins).
