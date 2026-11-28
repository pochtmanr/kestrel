# Architecture: Kestrel Wallet (iOS)

## Summary

Single-scene SwiftUI app. `AppModel` (`@Observable`, main actor) owns the app stage and the on-chain
data. Screens read it from the environment. Reads go straight to TronGrid. A USDT send is built by
TronGrid, signed on the device and broadcast through TronGrid. The widget reads a snapshot the app writes
to App Group defaults, and refreshes from TronGrid itself.

## Targets

| Target | Sources | Notes |
|---|---|---|
| `Kestrel` | `Kestrel/` | The app. Depends on `libsecp256k1` and embeds the widget |
| `KestrelWidget` | `KestrelWidget/` + `Kestrel/Shared/` | Home and lock screen balance widget |
| `KestrelTests` | `KestrelTests/` | Crypto vectors plus a live TronGrid read |

## Folders

- `App/`: `KestrelApp` (entry point, `RootView` stage switch, `MainTabView` with the Wallet and Activity
  tabs; pushed screens hide the tab bar) and `AppModel` (stage: setup → createPIN → locked → unlocked, balances, history,
  erase, widget snapshot). In DEBUG, `-demo` loads sample data.
- `Shared/` (app + widget): `Theme` (design tokens), `Brand` (name and app group from Info.plist),
  `TronClient` (reads), `TronAddress`, `Encoding` (hex, Base58), `SharedWallet` (widget snapshot).
- `Services/` (app only): `SecureStore` (Keychain, `WalletVault`, `PinStore`, `Biometrics`,
  `SupportIdentity`), `TronClient+Send` (build, sign, broadcast), `Backend` (Supabase client),
  `PriceClient` (CoinGecko markets: price, changes, sparkline, stats, and price history up to 1 year; the
  5-year chart comes from Kraken's public weekly candles; coin ids only, never the address), `ChartCache`
  (charts on disk, prices only), `TronClient+Fees` (read-only fee estimate for a USDT transfer: simulated
  energy, account resources, chain prices), `PriceAlertStore` and `AlertNotifier` (on-device price alerts as
  local notifications; no server) and `ActivityStore` (cached full USDT history and fees).
- `Crypto/`: `Mnemonic` (BIP-39), `TronKeys` (BIP-32/44, address, signing), `Secp256k1`, `Keccak256`.
- `UI/Components.swift`: shared views and styles (buttons, surfaces, QR code, support button,
  appearance).
- `Features/`: Onboarding (create, restore, backup), Lock (PIN setup, lock screen, PIN confirm sheet),
  Wallet (home, transfer detail, fee info), Activity (timeframe charts, insights, search and filters;
  `ActivityAnalytics` holds the pure balance/flow/insight maths), Currencies (portfolio value, allocation, coin list with sparklines and search, and the coin screen with its
  price chart, position, market stats and transfers or fees; `TokenKind` is the coin registry and `Market` the pure maths), Send (form, QR scanner), Deposit (receive: QR and `tron:` payment-request URI, live "Received" detection; pure logic in `ReceiveLogic`),
  Settings, Support (Chatwoot sheet and `SupportConfig`).

## Theming

Every colour, corner radius, spacing step and amount font comes from `Theme` (`Shared/Theme.swift`).
Accent and background colours live in asset catalogs (`Brand/Kestrel.xcassets`, `Resources/Assets.xcassets`,
`KestrelWidget/Assets.xcassets`). A redesign changes the tokens, the assets and `UI/Components.swift`.

## Localisation

`Resources/Localizable.xcstrings` is the string catalog (English at launch). `SWIFT_EMIT_LOC_STRINGS`
collects literals from `Text`, `Label`, `LocalizedStringKey` parameters and `String(localized:)`. Add a
language by adding it in the catalog.

## Networking

`TronClient` uses `URLSession.shared` against `https://api.trongrid.io` with a public project key (quota
only). It reads the USDT balance (`triggerconstantcontract`), the TRX balance and USDT transfer history,
including paged history (`usdtHistoryPage`, 200 per page, `fingerprint` cursor) and the fees the wallet
paid (`transactionFees`). `TronClient+Send` asks
TronGrid to build a TRC-20 `transfer`, signs the txID and broadcasts it. Errors map to
`TronClient.Failure`.

`ActivityStore` (owned by `AppModel.activity`) keeps the wallet's USDT history and fees in a JSON file in
Application Support (`activity-<address>.json`). It holds public chain data only, never keys. `sync()` fetches
only what's newer than the cache; `ensureCoverage(since:)` pages backwards (up to 10 pages per call) when the
Activity tab needs an older timeframe. A 429 backs off 30 s → 240 s. No server is involved: the address never
leaves the device except to TronGrid.

`Backend` talks to the Supabase project at `https://supabase.holylabs.net` with the public anon key:
`invoke(_:body:)` for edge functions (`functions/v1/<name>`), and `select` / `insert` for PostgREST
tables (`rest/v1/<table>`). Calls are anonymous unless a user access token is passed. Errors map to
`Backend.Failure`. Nothing in the core wallet depends on it yet: add a feature on top, and keep the wallet
working when the backend is unreachable.

## Support

`SupportConfig` holds the Chatwoot base URL and website token, plus the terms and privacy URLs. While
they're empty, the support button and the legal rows are hidden.
