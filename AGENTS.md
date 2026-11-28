# AGENTS.md: orientation for AI coding agents

Read this first. Humans: start with [README.md](README.md).

## What this is

Kestrel Wallet: a native SwiftUI iOS 17+ app (Swift 6), a **self-custody USDT-on-TRON wallet**, with a
WidgetKit balance widget. Publisher: Simnetiq Ltd. There's no card, no fiat, no KYC and no account. The
wallet talks to TronGrid only; market prices come from CoinGecko, and the 5-year chart from Kraken's
public candles (coin names only, never the address). The Supabase backend (`Backend`) is for optional server-side features
(e.g. push for incoming transfers). The support chat is used once it's configured.

## Map: where to look for what

| You need to… | Go to |
|---|---|
| Change a target, bundle ID, version, team, plist value or URL scheme | `project.yml`, then `xcodegen generate` |
| App state, stages (setup → PIN → locked → unlocked), tabs | `Kestrel/App/AppModel.swift`, `Kestrel/App/KestrelApp.swift` |
| iPad / unfolded-iPhone shell | `Kestrel/App/MainSplitView.swift`: `SidebarTabShell` (iOS 18+, the system's top tab bar that opens into a sidebar) and `MainSplitView` (iOS 17 fallback); regular width only, compact keeps the bottom tab bar |
| Wide-screen layout (two columns, widths) | `AdaptiveColumns`, `readableWidth(_:)` in `Kestrel/UI/Components.swift`; `Theme.Layout` |
| Change a screen | `Kestrel/Features/<Area>/` (Wallet, Activity, Currencies, Send, Deposit = receive, Lock, Onboarding, Settings, Support) |
| Add a coin, or change prices, charts and market data | `TokenKind` in `Kestrel/Features/Currencies/TokenKind.swift` (the coin registry), `Kestrel/Services/PriceClient.swift` (CoinGecko; Kraken for the 5-year range), `Market.swift` (models, parsers), `PriceChartView.swift` / `ExpandedChartView.swift` |
| Price alerts (on-device, local notifications) | `Kestrel/Features/Currencies/PriceAlert.swift`, `PriceAlertsView.swift`, `Kestrel/Services/PriceAlertStore.swift`, `AlertNotifier.swift`; wired in `KestrelApp.swift` |
| Colours, radii, spacing, type | `Kestrel/Shared/Theme.swift` (design tokens, shared with the widget) |
| A button, row, sheet style | `Kestrel/UI/Components.swift` |
| TronGrid reads (balance, history) | `Kestrel/Shared/TronClient.swift` (shared with the widget) |
| Building, signing and broadcasting a USDT transfer | `Kestrel/Services/TronClient+Send.swift` |
| Keys: mnemonic, derivation, signing, hashing | `Kestrel/Crypto/` |
| Keychain (phrase encrypted under the PIN, its Face ID copy, wrong-PIN count) | `Kestrel/Services/SecureStore.swift`; model in `docs/SECURITY.md` |
| Checking a node-built transfer before signing; address-poisoning checks | `Kestrel/Crypto/TransferVerifier.swift`, `Kestrel/Features/Send/AddressSafety.swift` |
| App-switcher privacy cover, keyboard-extension block | `Kestrel/App/PrivacyCurtain.swift` |
| Backend (Supabase edge functions, PostgREST tables) | `Kestrel/Services/Backend.swift` |
| Support chat and legal URLs | `SupportConfig` in `Kestrel/Features/Support/SupportView.swift` |
| App name and app group at runtime | `Kestrel/Shared/Brand.swift` |
| Widget | `KestrelWidget/BalanceWidget.swift`, snapshot model in `Kestrel/Shared/SharedWallet.swift` |
| UI strings | `Kestrel/Resources/Localizable.xcstrings`, `InfoPlist.xcstrings`, `KestrelWidget/Localizable.xcstrings` (English, Russian, Simplified Chinese) |
| In-app language, theme, text size | `Kestrel/Shared/AppLanguage.swift` (`AppLanguage`, `tr()`), `Kestrel/UI/AppPreferences.swift`, `Kestrel/Features/Settings/` (`AppearanceView`, `LanguagePickerView`) |
| Network fees explainer | `Kestrel/Features/Wallet/NetworkFeeInfoView.swift` |
| Live network-fee estimate for a transfer | `Kestrel/Features/Send/FeeEstimate.swift` (formula), `Kestrel/Services/TronClient+Fees.swift` (read-only node calls, `FeeEstimator`) |
| Website (kastrel.xyz): landing page, privacy policy, terms, legal pages | `website/` (Astro, static; see `website/README.md`). Facts in `website/src/site.config.mjs`; legal research in `website/docs/legal-research.md`. If the app starts contacting a new service, update the privacy policy in all three languages |
| Plan and backlog | `docs/roadmap/KESTREL_PLAN.md` |
| App Store screenshots | `scripts/capture-screenshots.sh` (raw shots), `fastlane/screenshot-studio/` (framed images) |
| App Store listing and uploads | `fastlane/metadata/`, `fastlane/Fastfile`, `fastlane/README.md` |

## Verify a change

```bash
xcodegen generate     # after editing project.yml (never hand-edit Kestrel.xcodeproj)
xcodebuild -project Kestrel.xcodeproj -scheme Kestrel -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Kestrel.xcodeproj -scheme Kestrel -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build test
```

`CODE_SIGNING_ALLOWED=NO` is for compile checks only. **Never install that build on a simulator**: it
has no entitlements, so it can't see the wallet the signed app saved in the Keychain. It opens on
onboarding, which looks like the user was logged out. To install or run the app, build without that flag.

Launch flags (debug builds): `-demo` loads a sample wallet with no network; `-welcome` shows onboarding
without touching the Keychain; `-route <screen>` opens a screen at launch (with `-demo`: `receive`,
`activity`, `currencies`, `fees`, `settings`, `appearance`, `language`, `send`, `transfer`, `lock`, `coin-usdt`, `coin-trx`).
With a `coin-…` route, `-coin-expanded` opens the full-screen chart and `-coin-alerts` that coin's price alerts.
`-app.language ru` (or `zh-Hans`, `en`), `-appearance light|dark` and `-app.textSize 0…6` override the Settings choices for one launch.

Wide screens: check iPhone, iPad 13" (portrait), and an iPad in Split View (compact: the phone UI). The
`iPhone Duo` simulator's inner display can't be switched on from the command line; unfold it from Xcode.

Pick a simulator that exists (`xcrun simctl list devices available`). The live TronGrid test skips
offline and can hit HTTP 429 rate limits; if it does, re-run it.

## Rules that matter here

1. **`project.yml` is the source of truth.** `Kestrel.xcodeproj` is generated and committed. Regenerate
   it and commit both together.
2. **`Kestrel/Shared/` is compiled into the widget too.** Keep it free of app-only APIs (`UIApplication`,
   app-only types).
3. **Crypto is safety-critical.** Any change under `Kestrel/Crypto/`, `SecureStore.swift` or
   `TronClient+Send.swift` must keep `KestrelTests/CryptoVectorTests.swift`, `TransferVerifierTests.swift` and
   `WalletVaultTests.swift` passing. Add vectors for new
   paths. Never log or persist the mnemonic or private keys outside the Keychain.
4. **Use theme tokens**, not literals, for colours, radii and amount fonts.
5. **User-facing text must be localisable.** Use `Text("literal")`, `LocalizedStringKey` parameters, or
   `tr("…")` for strings built in code (not `String(localized:)`, which ignores the in-app language).
   A command-line build doesn't sync the catalogs: add new keys to the `.xcstrings` files with their
   Russian and Chinese text. Every call to action is a capsule (`PrimaryButtonStyle`, `SecondaryButtonStyle`).
6. **No secrets in the repo.** The Supabase anon key and a Chatwoot website token are public by design.
   Service-role keys never go in the app. App Store Connect keys live
   outside the repo.
7. **Keep it wallet-only.** No card, fiat on-ramp or KYC flows, and no code from the codebase this was
   forked from that serves those. Never send the phrase, keys or PIN to the backend; the wallet must keep
   working if the backend is down.

## Conventions

- SwiftUI + Observation (`@Observable`), async/await, Swift 6 strict concurrency. No third-party UI libraries.
- One feature area per folder. A view file holds its private subviews.
- Comments explain *why*, not *what*.
- Docs live in `docs/`. Keep them true when you change behaviour.
