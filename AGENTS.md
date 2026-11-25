# AGENTS.md: orientation for AI coding agents

Read this first. Humans: start with [README.md](README.md).

## What this is

Kestrel Wallet: a native SwiftUI iOS 17+ app (Swift 6), a **self-custody USDT-on-TRON wallet**, with a
WidgetKit balance widget. Publisher: Simnetiq Ltd. There's no card, no fiat, no KYC and no account. The
wallet talks to TronGrid only. The Supabase backend (`Backend`) is for optional server-side features
(e.g. push for incoming transfers). The support chat is used once it's configured.

## Map: where to look for what

| You need to… | Go to |
|---|---|
| Change a target, bundle ID, version, team, plist value or URL scheme | `project.yml`, then `xcodegen generate` |
| App state, stages (setup → PIN → locked → unlocked), tabs | `Kestrel/App/AppModel.swift`, `Kestrel/App/KestrelApp.swift` |
| Change a screen | `Kestrel/Features/<Area>/` (Wallet, Activity, Currencies, Send, Deposit = receive, Lock, Onboarding, Settings, Support) |
| Add a coin, or change prices, charts and market data | `TokenKind` in `Kestrel/Features/Currencies/TokenKind.swift` (the coin registry), `Kestrel/Services/PriceClient.swift` (CoinGecko) |
| Colours, radii, spacing, type | `Kestrel/Shared/Theme.swift` (design tokens, shared with the widget) |
| A button, row, sheet style | `Kestrel/UI/Components.swift` |
| TronGrid reads (balance, history) | `Kestrel/Shared/TronClient.swift` (shared with the widget) |
| Building, signing and broadcasting a USDT transfer | `Kestrel/Services/TronClient+Send.swift` |
| Keys: mnemonic, derivation, signing, hashing | `Kestrel/Crypto/` |
| Keychain (mnemonic, PIN hash, Face ID flag) | `Kestrel/Services/SecureStore.swift` |
| Backend (Supabase edge functions, PostgREST tables) | `Kestrel/Services/Backend.swift` |
| Support chat and legal URLs | `SupportConfig` in `Kestrel/Features/Support/SupportView.swift` |
| App name and app group at runtime | `Kestrel/Shared/Brand.swift` |
| Widget | `KestrelWidget/BalanceWidget.swift`, snapshot model in `Kestrel/Shared/SharedWallet.swift` |
| UI strings | `Kestrel/Resources/Localizable.xcstrings` (English at launch) |
| Plan and backlog | `docs/roadmap/KESTREL_PLAN.md` |

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
without touching the Keychain; `-route <screen>` opens a screen at launch.

Pick a simulator that exists (`xcrun simctl list devices available`). The live TronGrid test skips
offline and can hit HTTP 429 rate limits; if it does, re-run it.

## Rules that matter here

1. **`project.yml` is the source of truth.** `Kestrel.xcodeproj` is generated and committed. Regenerate
   it and commit both together.
2. **`Kestrel/Shared/` is compiled into the widget too.** Keep it free of app-only APIs (`UIApplication`,
   app-only types).
3. **Crypto is safety-critical.** Any change under `Kestrel/Crypto/`, `SecureStore.swift` or
   `TronClient+Send.swift` must keep `KestrelTests/CryptoVectorTests.swift` passing. Add vectors for new
   paths. Never log or persist the mnemonic or private keys outside the Keychain.
4. **Use theme tokens**, not literals, for colours, radii and amount fonts.
5. **User-facing text must be localisable.** Use `Text("literal")`, `LocalizedStringKey` parameters, or
   `String(localized:)` for strings built in code.
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
