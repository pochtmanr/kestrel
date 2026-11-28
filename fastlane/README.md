# fastlane: Kestrel Wallet store listing

App Store metadata and screenshots for `com.simnetiq.kestrel` ("Kestrel Wallet", Simnetiq Ltd).
These lanes never build, upload a binary or submit for review (`submit_for_review: false`,
`automatic_release: false`). Run them from the repo root.

> The App Store Connect app record does not exist yet. Create it in App Store Connect first
> (bundle ID `com.simnetiq.kestrel`, name "Kestrel Wallet"); every lane fails until it does.

## Lanes

| Lane | What it does |
|---|---|
| `fastlane ios upload_metadata` | everything in `metadata/`: name, subtitle, description, keywords, promo text, release notes, URLs, copyright, category, review notes. No screenshots |
| `fastlane ios upload_release_text` | only promotional text + release notes (`metadata-release-text/`, symlinks into `metadata/`) |
| `fastlane ios upload_screenshots` | iPhone 6.9″ + iPad 13″ from `screenshots/<locale>/`; replaces the sets of every locale on disk |
| `fastlane ios upload_duo_screenshots` | iPhone Duo from `screenshots-duo/<locale>/` via Spaceship (display type `APP_IPHONE_DUO`) |
| `fastlane ios download_metadata` | pulls the live/edit metadata into `metadata-downloaded/` (set `DOWNLOAD_PATH=fastlane/metadata` to overwrite) |

Screenshots come from `screenshot-studio/` (see its README): export, then `scripts/collect.sh` fills
`screenshots/` and `screenshots-duo/`.

## Environment

| Variable | Needed by | |
|---|---|---|
| `ASC_KEY_ID` | all | App Store Connect API key ID |
| `ASC_ISSUER_ID` | all | API key issuer ID |
| `ASC_KEY_FILEPATH` | all | path to the `.p8`, kept outside the repo |
| `ASC_APP_VERSION` | all except `download_metadata` | the version record in App Store Connect, e.g. `1.0.0` |
| `SCREENSHOTS_PATH` | `upload_screenshots` | default `fastlane/screenshots` |
| `DUO_PATH` | `upload_duo_screenshots` | default `fastlane/screenshots-duo` |

**The `ASC_APP_VERSION` gotcha:** deliver matches the *version record name* in App Store Connect,
which is not always `MARKETING_VERSION` (a 1.0.1 build can ship in a record named "1.0"). There is
no default on purpose: a stale default silently writes text or screenshots to the wrong, possibly
already released, version. Check the record before every upload.

## Before the first upload

- `support_url.txt`, `privacy_url.txt` and `marketing_url.txt` are `TODO` placeholders, because
  `SupportConfig` in the app has no URLs yet. `upload_metadata` refuses to run while any `TODO` is left.
  Remove `marketing_url.txt` if there is no marketing page.
- App Store Connect does not allow "What's New" on an app's first version. If deliver rejects
  `release_notes.txt` for 1.0.0, move it out of `metadata/en-US/` for that upload.

## Adding a locale

1. Create `metadata/<locale>/` with the same files as `en-US/` (the studio derives its locale list from
   these folder names).
2. Write `screenshot-studio/copy/<locale>.json`.
3. Add the locale to `metadata-release-text/` if release text should go up separately.

Translations are written by hand by a person. Never generate them with a script, a translation
service or an LLM API.
