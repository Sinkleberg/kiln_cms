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
  System → Plugins says whether a backend is receiving uploads. The Cloudflare
  Images plugin itself ships separately.
  ([#1955](https://github.com/The-Verscienta/kiln_cms/issues/1955))
