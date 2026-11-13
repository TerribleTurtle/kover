# Kover Dev: Fixes, Features & Test Builds

Daily-driver fork of [`@rodonisi`](https://github.com/rodonisi)'s [**Kover**](https://github.com/rodonisi/kover) targeting open issues and feature requests not yet addressed in the official build.

Every fix (`fix/*`), feature (`feat/*`) and CI workflow (`ci/*`) lives on its own clean branch off `upstream/main` so it can be sent upstream as a pull request and dropped once it lands in the official app.

### How This Repo Is Organized

- **`main` mirrors [`rodonisi/kover:main`](https://github.com/rodonisi/kover) 1:1.** I never commit directly to `main` on GitHub so the default branch always stays even with upstream.
- **One issue, feature or CI task = one branch (`fix/*`, `feat/*` or `ci/*`).** Every branch starts cleanly from `upstream/main` so it is easy to review or cherry-pick on its own.
- **Side-by-side `Kover Dev` APK ([Releases](https://github.com/TerribleTurtle/kover/releases)).** The `dev-ota` branch merges all active `fix/*`, `feat/*` and `ci/*` branches on top of `upstream/main` and builds a signed `Kover Dev` (`com.rodonisi.kover.dev`) APK for `arm64-v8a`. Because it uses the `.dev` package ID, it installs right alongside the official Kover app without overwriting your main install.

---

## Active Branches (`6` Active, `10` Merged Upstream)

### 1. Open Upstream Pull Requests

| Issue | Branch & Diff | Upstream PR | Summary |
|---|---|---|---|

---

### 2. Staged Branches (Live on This Fork, Queued for Upstream PRs)

To avoid overwhelming the upstream PR queue, I keep these staged on their own branches until open PRs are reviewed. Each branch is rebased cleanly on `upstream/main` and can be cherry-picked independently:

| Issue | Branch & Diff | Status | Summary |
|---|---|---|---|
| Local Dev / OTA | [`feat/dev-flavor`](https://github.com/TerribleTurtle/kover/tree/feat/dev-flavor) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:feat/dev-flavor), `+19/-6`) | Local Only | Configures side-by-side 'Kover Dev' (com.rodonisi.kover.dev) package ID and key.properties signing fallback so Dev OTA and USB test builds install alongside Play Store Kover. |
| Local Dev / OTA | [`fix/spread-mode-compact-crash`](https://github.com/TerribleTurtle/kover/tree/fix/spread-mode-compact-crash) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:fix/spread-mode-compact-crash), `+58/-15`) | Staged | Falls back from two-page spread mode to horizontal paging on compact portrait screens across EPUB and comic readers, prevents the Reader Settings sheet from crashing when spread mode is hidden, and restores two-page spreads when returning to wider viewports. |
| Local Dev / OTA | [`ci/speedup-and-gradle-cache`](https://github.com/TerribleTurtle/kover/tree/ci/speedup-and-gradle-cache) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:ci/speedup-and-gradle-cache), `+19/-1`) | Staged | Caches Android Gradle builds with the open-source basic setup-gradle provider, deduplicates DB schema, format, analyzer, and test steps onto the web matrix leg while preserving all six Universal/native builds and check names, restricts workflow permissions to read-only, and cancels superseded non-main runs safely across forks. |
| Local Dev / OTA | [`fix/unread-progress-sync`](https://github.com/TerribleTurtle/kover/tree/fix/unread-progress-sync) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:fix/unread-progress-sync), `+49/-14`) | Staged | Syncs chapters marked unread on Kavita Web or other clients back to Kover, clears stale EPUB scroll positions across read/unread toggles and zero-page server responses, restricts missing-xpath EPUB refreshes to clean partially read chapters, and preserves On Deck removals on zero-page progress while clearing them when marking items read. |
| Local Dev / OTA | [`ci/release-apk-sentry`](https://github.com/TerribleTurtle/kover/tree/ci/release-apk-sentry) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:ci/release-apk-sentry), `+10/-1`) | Staged | Passes the Sentry auth token to the release APK workflow, populates the runtime Sentry DSN via dart-define during the release APK build, and uploads debug symbols with the Sentry Dart plugin before attaching the APK to the GitHub Release. |
| Local Dev / OTA | [`fix/unvolumed-chapter-navigation`](https://github.com/TerribleTurtle/kover/tree/fix/unvolumed-chapter-navigation) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:fix/unvolumed-chapter-navigation), `+65/-39`) | Staged | Restores previous and next chapter navigation for loose chapters and specials outside numbered volumes, and orders unread series continue points across numbered volumes, loose chapters, and specials. |

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
| [#491](https://github.com/rodonisi/kover/issues/491) | `fix/default-fallback-locale` ([`2b5ccaea`](https://github.com/rodonisi/kover/commit/2b5ccaea)) | [**PR #492**](https://github.com/rodonisi/kover/pull/492) *(Merged)* | Sets English as the preferred fallback language so devices configured with an unsupported system language (such as Norwegian) launch in English instead of German. |
| [#495](https://github.com/rodonisi/kover/issues/495) | `fix/reader-slider-gesture-nav` ([`0ddea3b7`](https://github.com/rodonisi/kover/commit/0ddea3b7)) | [**PR #498**](https://github.com/rodonisi/kover/pull/498) *(Merged)* | Prevents Android bottom system gesture swipes from waking the reader overlay or accidentally jumping pages on the bottom slider, while keeping smooth thumb scrubbing and chapter snackbar spacing. |
| [#497](https://github.com/rodonisi/kover/issues/497) | `fix/android-adaptive-icon` ([`d2236462`](https://github.com/rodonisi/kover/commit/d2236462)) | [**PR #499**](https://github.com/rodonisi/kover/pull/499) *(Merged)* | Configure Android 8+ adaptive launcher icon layers so Pixel and modern Android launchers fill the circular icon mask cleanly. |

---

## Using the `Kover Dev` Test APK ([Releases](https://github.com/TerribleTurtle/kover/releases))

If you are running into one of the issues listed above or want to try an unmerged feature before it lands in an official Kover release:

1. Grab the latest `Kover Dev` APK from [**Releases**](https://github.com/TerribleTurtle/kover/releases) (or point [Obtainium](https://github.com/ImranR98/Obtainium) at `https://github.com/TerribleTurtle/kover`).
2. It installs as **Kover Dev** (`com.rodonisi.kover.dev`) alongside the official Kover app so your normal setup stays untouched.
3. Each release is built automatically by GitHub Actions from [`dev-ota`](https://github.com/TerribleTurtle/kover/tree/dev-ota), which is simply `upstream/main` (`1.0.0+1`) plus the 6 active branches listed above.
4. **Please don't bug rodonisi with issues specific to this test build** - if you notice something odd while using `Kover Dev`, double-check whether it also happens on the official release from [`rodonisi/kover`](https://github.com/rodonisi/kover/releases) before opening an upstream issue.
