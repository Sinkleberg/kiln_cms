# KilnCMS Unreleased — full release notes

The long-form entries behind the Unreleased section of
[CHANGELOG.md](../../CHANGELOG.md), as they were written when each change
merged. `CHANGELOG.md` carries the one-line summary of each; this file
carries the reasoning.

## Added

<a id="kilncmsdev-now-publishes-kilns-security-policy-at-security-and-a-security"></a>

- **kilncms.dev now publishes Kiln's security policy at `/security`, and a
  security notice per published GitHub advisory at
  `/security-notices/<ghsa-id>`, with a feed.** A new workflow,
  `publish-security.yml`, runs `scripts/publish_security.exs` daily, when a
  release is published, and when `.github/SECURITY.md` changes on `main`.
  The page is `SECURITY.md`, with its relative links pointed at GitHub, plus
  the list of notices. Each notice is an entry of a `security_notice`
  content type whose custom fields are `package`, `affected_versions`,
  `patched_versions`, `severity`, `advisory_id`, `cve_id`, `published_on`
  and `advisory_url`. `package` is `kiln_cms` for the core and a plugin's
  Hex name for a plugin's notice, so the plugin registry (#1447) can share
  the type and its feed at `/security-notices/feed.xml`. A withdrawn advisory
  is not published, and the script never unpublishes a notice. The type is a
  one-time setup on the site; the script names any field it is missing.
  `SECURITY.md` and the README link to the page and the feed. Nothing
  changes for a self-hosted instance: the script and workflow publish to
  kilncms.dev only. The per-site `security.txt` this issue also asked for
  shipped in 1.1.0 (#1881).
  ([#1873](https://github.com/The-Verscienta/kiln_cms/issues/1873))

