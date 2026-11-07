# Kover Dev: Fixes, Features & Test Builds

Daily-driver fork of [`@rodonisi`](https://github.com/rodonisi)'s [**Kover**](https://github.com/rodonisi/kover) targeting open issues and feature requests not yet addressed in the official build.

Every fix (`fix/*`) and feature (`feat/*`) lives on its own clean branch off `upstream/main` so it can be sent upstream as a pull request and dropped once it lands in the official app.

### How This Repo Is Organized

- **`main` mirrors [`rodonisi/kover:main`](https://github.com/rodonisi/kover) 1:1.** I never commit directly to `main` on GitHub so the default branch always stays even with upstream.
- **One issue or feature = one branch (`fix/*` or `feat/*`).** Every branch starts cleanly from `upstream/main` so it is easy to review or cherry-pick on its own.
- **Side-by-side `Kover Dev` APK ([Releases](https://github.com/TerribleTurtle/kover/releases)).** The `dev-ota` branch merges all active `fix/*` and `feat/*` branches on top of `upstream/main` and builds a signed `Kover Dev` (`com.rodonisi.kover.dev`) APK for `arm64-v8a`. Because it uses the `.dev` package ID, it installs right alongside the official Kover app without overwriting your main install.

---

## Active Branches (`6` Active, `7` Merged Upstream)

### 1. Open Upstream Pull Requests

| Issue | Branch & Diff | Upstream PR | Summary |
|---|---|---|---|
| [#488](https://github.com/rodonisi/kover/issues/488) | [`fix/large-pdf-sync`](https://github.com/TerribleTurtle/kover/tree/fix/large-pdf-sync) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:fix/large-pdf-sync), `+195/-37`) | [**PR #493**](https://github.com/rodonisi/kover/pull/493) | Streams PDF downloads directly to disk via a temporary file and opens downloaded PDFs from file storage so 350-520 MB+ books download and render without out-of-memory crashes. |
| [#491](https://github.com/rodonisi/kover/issues/491) | [`fix/default-fallback-locale`](https://github.com/TerribleTurtle/kover/tree/fix/default-fallback-locale) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:fix/default-fallback-locale), `+2/-0`) | [**PR #492**](https://github.com/rodonisi/kover/pull/492) | Sets English as the preferred fallback language so devices configured with an unsupported system language (such as Norwegian) launch in English instead of German. |

---

### 2. Staged Branches (Live on This Fork, Queued for Upstream PRs)

To avoid overwhelming the upstream PR queue, I keep these staged on their own branches until open PRs are reviewed. Each branch is rebased cleanly on `upstream/main` and can be cherry-picked independently:

| Issue | Branch & Diff | Status | Summary |
|---|---|---|---|
| Local Dev / OTA | [`feat/dev-flavor`](https://github.com/TerribleTurtle/kover/tree/feat/dev-flavor) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:feat/dev-flavor), `+19/-6`) | Staged | Configures side-by-side 'Kover Dev' (com.rodonisi.kover.dev) package ID and key.properties signing fallback so Dev OTA and USB test builds install alongside Play Store Kover. |
| Local Dev / OTA | `fix/reader-complete-sync` (`+113/-115`) | Staged | Immediately pushes chapter completion and mark-read/unread updates to the Kavita server and triggers progress sync after the reader 100ms save debounce flushes on both route pop and next-chapter navigation. |
| Local Dev / OTA | `fix/breakpoints-keep-alive` (`+1/-2`) | Staged | Annotates the Breakpoints provider with @Riverpod(keepAlive: true) instead of calling ref.keepAlive() inside build() so flutter analyze passes under riverpod_lint 3.2.0. |
| [#416](https://github.com/rodonisi/kover/issues/416) | `feat/epub-footnote-links` (`+2012/-16`) | Staged | Support tapping in-book chapter links, external web links, and footnote references in the EPUB reader with a themed footnote preview sheet. |

---

### 3. Previously Merged Upstream

| Issue | Branch | Upstream PR | Summary |
|---|---|---|---|
| [#459](https://github.com/rodonisi/kover/issues/459) | `fix/invalid-api-key-459` ([`28aa04bd`](https://github.com/rodonisi/kover/commit/28aa04bd)) | [**PR #469**](https://github.com/rodonisi/kover/pull/469) *(Merged)* | Shows a dedicated 'Invalid Credentials' warning without retrying when the server rejects the API key (HTTP 401/403), and shows 'Connection Error' in Settings when the server is unreachable. |
| [#352](https://github.com/rodonisi/kover/issues/352) | `fix/settings-modals-back-gesture-352` ([`ffc75ce8`](https://github.com/rodonisi/kover/commit/ffc75ce8)) | [**PR #470**](https://github.com/rodonisi/kover/pull/470) *(Merged)* | Fixes the App Info modal, Clear Database dialog, and Keybind capture dialog closing after the Settings page when using the Android back gesture. |
| [#305](https://github.com/rodonisi/kover/issues/305) | `feat/expand-search-305` ([`b0274094`](https://github.com/rodonisi/kover/commit/b0274094)) | [**PR #471**](https://github.com/rodonisi/kover/pull/471) *(Merged)* | Expands global search and in-page list filters to match authors/people, aliases, genres, tags, chapter ISBNs, and parent series titles on volumes/chapters with multi-word token matching and 3-tier title-first ranking. |
| Proactive Audit | `fix/epub-text-indent-preprocessor` ([`dff22791`](https://github.com/rodonisi/kover/commit/dff22791)) | [**PR #479**](https://github.com/rodonisi/kover/pull/479) *(Merged)* | Fix EPUB text-indent overrides on Tables of Contents, copyright pages, centered headers, and opening paragraphs when books define a default paragraph indent. |
| [#484](https://github.com/rodonisi/kover/issues/484) | `fix/smart-filter-sorting` ([`28efa7f3`](https://github.com/rodonisi/kover/commit/28efa7f3)) | [**PR #486**](https://github.com/rodonisi/kover/pull/486) *(Merged)* | Preserves the server-evaluated sort order for smart filters across the homepage and smart filter drill-down page by default while still allowing manual sort overrides. |
| [#480](https://github.com/rodonisi/kover/issues/480) | `fix/volume-end-next-chapter` ([`907f9c8b`](https://github.com/rodonisi/kover/commit/907f9c8b)) | [**PR #489**](https://github.com/rodonisi/kover/pull/489) *(Merged)* | Allows moving to the previous or next chapter across volume boundaries by ordering series chapters by volume number before chapter order. |
| Proactive Audit | `fix/continue-point-volume-order` ([`f16bd57a`](https://github.com/rodonisi/kover/commit/f16bd57a)) | [**PR #490**](https://github.com/rodonisi/kover/pull/490) *(Merged)* | Orders series continue-point queries by volume number before chapter order so multi-volume series with per-volume chapter numbering select unread chapters in earlier volumes first. |

---

## Using the `Kover Dev` Test APK ([Releases](https://github.com/TerribleTurtle/kover/releases))

If you are running into one of the issues listed above or want to try an unmerged feature before it lands in an official Kover release:

1. Grab the latest `Kover Dev` APK from [**Releases**](https://github.com/TerribleTurtle/kover/releases) (or point [Obtainium](https://github.com/ImranR98/Obtainium) at `https://github.com/TerribleTurtle/kover`).
2. It installs as **Kover Dev** (`com.rodonisi.kover.dev`) alongside the official Kover app so your normal setup stays untouched.
3. Each release is built automatically by GitHub Actions from [`dev-ota`](https://github.com/TerribleTurtle/kover/tree/dev-ota), which is simply `upstream/main` (`1.0.0+1`) plus the 6 active branches listed above.
4. **Please don't bug rodonisi with issues specific to this test build** - if you notice something odd while using `Kover Dev`, double-check whether it also happens on the official release from [`rodonisi/kover`](https://github.com/rodonisi/kover/releases) before opening an upstream issue.
