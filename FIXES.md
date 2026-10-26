# Kover Dev: Fixes, Features & Test Builds

Daily-driver fork of [`@rodonisi`](https://github.com/rodonisi)'s [**Kover**](https://github.com/rodonisi/kover) targeting open issues and feature requests not yet addressed in the official build.

Every fix (`fix/*`) and feature (`feat/*`) lives on its own clean branch off `upstream/main` so it can be sent upstream as a pull request and dropped once it lands in the official app.

### How This Repo Is Organized

- **`main` mirrors [`rodonisi/kover:main`](https://github.com/rodonisi/kover) 1:1.** I never commit directly to `main` on GitHub so the default branch always stays even with upstream.
- **One issue or feature = one branch (`fix/*` or `feat/*`).** Every branch starts cleanly from `upstream/main` so it is easy to review or cherry-pick on its own.
- **Side-by-side `Kover Dev` APK ([Releases](https://github.com/TerribleTurtle/kover/releases)).** The `dev-ota` branch merges all active `fix/*` and `feat/*` branches on top of `upstream/main` and builds a signed `Kover Dev` (`com.rodonisi.kover.dev`) APK for `arm64-v8a`. Because it uses the `.dev` package ID, it installs right alongside the official Kover app without overwriting your main install.

---

## Active Branches (`4` Active, `3` Merged Upstream)

### 1. Open Upstream Pull Requests

| Issue | Branch & Diff | Upstream PR | Summary |
|---|---|---|---|
| Proactive Audit | [`fix/epub-text-indent-preprocessor`](https://github.com/TerribleTurtle/kover/tree/fix/epub-text-indent-preprocessor) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:fix/epub-text-indent-preprocessor), `+28/-15`) | [**PR #479**](https://github.com/rodonisi/kover/pull/479) | Fix EPUB text-indent overrides on Tables of Contents, copyright pages, centered headers, and opening paragraphs when books define a default paragraph indent. |

---

### 2. Staged Branches (Live on This Fork, Queued for Upstream PRs)

To avoid overwhelming the upstream PR queue, I keep these staged on their own branches until open PRs are reviewed. Each branch is rebased cleanly on `upstream/main` and can be cherry-picked independently:

| Issue | Branch & Diff | Status | Summary |
|---|---|---|---|
| Local Dev / OTA | [`feat/dev-flavor`](https://github.com/TerribleTurtle/kover/tree/feat/dev-flavor) ([diff](https://github.com/rodonisi/kover/compare/main...TerribleTurtle:kover:feat/dev-flavor), `+19/-6`) | Staged | Configures side-by-side 'Kover Dev' (com.rodonisi.kover.dev) package ID and key.properties signing fallback so Dev OTA and USB test builds install alongside Play Store Kover. |
| [#416](https://github.com/rodonisi/kover/issues/416) | `fix/epub-footnote-reflow-416` (`+99/-20`) | Staged | Splits CJK text without spaces at character boundaries with punctuation rules and keeps inline footnote references attached to their preceding text across EPUB page breaks. |
| Local Dev / OTA | `fix/epub-large-chapter-perf` (`+97/-16`) | On Hold (waiting for upstream reflow rework) | Speeds up EPUB chapter loading and pagination by unwrapping single-child root wrappers, checking the image cache before decoding base64 data URIs with intrinsic header sizing, and skipping empty or duplicate HTML probes during measurement. |

---

### 3. Previously Merged Upstream

| Issue | Branch | Upstream PR | Summary |
|---|---|---|---|
| [#459](https://github.com/rodonisi/kover/issues/459) | `fix/invalid-api-key-459` ([`fe342f28`](https://github.com/rodonisi/kover/commit/fe342f28)) | [**PR #469**](https://github.com/rodonisi/kover/pull/469) *(Merged)* | Shows a dedicated 'Invalid Credentials' warning without retrying when the server rejects the API key (HTTP 401/403), and shows 'Connection Error' in Settings when the server is unreachable. |
| [#352](https://github.com/rodonisi/kover/issues/352) | `fix/settings-modals-back-gesture-352` ([`c26e2620`](https://github.com/rodonisi/kover/commit/c26e2620)) | [**PR #470**](https://github.com/rodonisi/kover/pull/470) *(Merged)* | Fixes the App Info modal, Clear Database dialog, and Keybind capture dialog closing after the Settings page when using the Android back gesture. |
| [#305](https://github.com/rodonisi/kover/issues/305) | `feat/expand-search-305` ([`00843a61`](https://github.com/rodonisi/kover/commit/00843a61)) | [**PR #471**](https://github.com/rodonisi/kover/pull/471) *(Merged)* | Expands global search and in-page list filters to match authors/people, aliases, genres, tags, chapter ISBNs, and parent series titles on volumes/chapters with multi-word token matching and 3-tier title-first ranking. |

---

## Using the `Kover Dev` Test APK ([Releases](https://github.com/TerribleTurtle/kover/releases))

If you are running into one of the issues listed above or want to try an unmerged feature before it lands in an official Kover release:

1. Grab the latest `Kover Dev` APK from [**Releases**](https://github.com/TerribleTurtle/kover/releases) (or point [Obtainium](https://github.com/ImranR98/Obtainium) at `https://github.com/TerribleTurtle/kover`).
2. It installs as **Kover Dev** (`com.rodonisi.kover.dev`) alongside the official Kover app so your normal setup stays untouched.
3. Each release is built automatically by GitHub Actions from [`dev-ota`](https://github.com/TerribleTurtle/kover/tree/dev-ota), which is simply `upstream/main` (`1.0.0+1`) plus the 4 active branches listed above.
4. **Please don't bug rodonisi with issues specific to this test build** - if you notice something odd while using `Kover Dev`, double-check whether it also happens on the official release from [`rodonisi/kover`](https://github.com/rodonisi/kover/releases) before opening an upstream issue.
