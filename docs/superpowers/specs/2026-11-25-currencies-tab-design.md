# Kestrel: Currencies tab

## Intent
The third tab is the system search tab today (`AssetSearchView`, titled "Coins"): a two-row list. Roman
wants it to become a normal **Currencies** tab with the same depth the Activity tab got, built so more
currencies can be added later. This round covers design and functionality for the two coins we have
(USDT, TRX). Adding new coins, tokens or networks is a later round.

## Goals
- A real tab: "Currencies" with its own icon, beside Wallet and Activity (no search role).
- A portfolio header (total value, 24h change, allocation) and a holdings list with sparklines.
- A rich coin screen: price chart with timeframes and scrubbing, your position, market stats, your
  transfers or fees, and actions.
- Every piece is driven by `TokenKind.allCases`, so a new coin means a new case plus its metadata and
  no layout changes.

## Non-goals
- New tokens, TRC-10, staking, or a market watchlist of coins not held.
- A portfolio value history chart. We only have full balance history for USDT, not TRX, so it would be
  wrong.
- Fiat currencies other than USD.

## Anti-goals
- The wallet ever depending on prices: no prices still means a working tab (holdings, actions).
- Sending the wallet address to CoinGecko. Requests name coins only.
- Revealing hidden balances (hide-balance applies to amounts, values and the allocation bar).

## Approaches considered
- **A. Portfolio + rich coin screens: picked by Roman.** Holdings-first list, with depth in the coin
  screen. It has real depth with two coins and scales.
- B. Market-first list (Stocks-like). Odd for a wallet whose main balance is a $1 stablecoin.
- C. Light touch (rename, add sparklines). Quick, but the tab stays thin.

## Design

### Tab
- `AppModel.Tab`: `search` becomes `currencies`. iOS 18+: `Tab("Currencies", systemImage: "chart.pie", value: .currencies)`
  with no `role: .search`. Remove the tab-level `.searchable` and `searchText` from `MainTabView`.
  iOS 17: the same tab via `.tabItem`.
- The search moves inside the tab: `.searchable` on the Currencies `NavigationStack` (pull down to show
  it), using the existing `searchTerms` matching.
- Files: `Kestrel/Features/Search/` becomes `Kestrel/Features/Currencies/`, with `CurrenciesView.swift`
  (tab), `CoinDetailView.swift` (coin screen), `PriceChart.swift` and `Market.swift` (models and
  derived maths). `TokenKind` and `TokenIcon` move out of `WalletView.swift` into
  `Kestrel/Features/Currencies/TokenKind.swift`.

### TokenKind becomes the registry
`enum TokenKind: String, CaseIterable, Hashable, Sendable` with `symbol`, `name`, `coingeckoID`
(`tether`, `tron`), `network` text, `usedFor` text, `searchTerms`, and the existing colour/icon. Adding a
coin later means one case plus these properties, plus a balance source in `AppModel.holding(of:)`.

### Market data (`PriceClient` grows into a market client)
- `markets()` → `coins/markets?vs_currency=usd&ids=<all coingeckoIDs>&sparkline=true&price_change_percentage=24h,7d`.
  Each coin gets a `MarketQuote`: price, 24h change %, 7d change %, sparkline (7d, about 168 points),
  market cap, 24h volume, 24h high/low, all-time high and its date.
- `AppModel.prices` stays (`[TokenKind: TokenPrice]`, derived from the quotes) so home, Activity and
  Send keep working unchanged. `AppModel.markets: [TokenKind: MarketQuote]` is added. Same once-a-minute
  throttle, and a failure keeps the last data.
- `chart(for:range:)` → `coins/{id}/market_chart?vs_currency=usd&days=<1|7|30|90|365>` (the free API answers 401 to `max`, so the ranges are 1D/7D/1M/3M/1Y, with no All), returning
  `[PricePoint(date, usd)]`. It's cached in memory per (coin, range) for 5 minutes and fetched when the
  coin screen shows a range. On HTTP 429 or a failure: keep the cached data if there is any, otherwise
  show the chart's empty state "Price history unavailable" with a Retry button.
- Decoding lives in static `parse…` functions so it can be unit-tested from JSON fixtures.

### Currencies tab
```
 Currencies                          (large title, pull-down search)
   Portfolio                    👁
   $2,493.07
   +$5.18 (+0.21%) today              green/red, value-weighted 24h change
   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░              allocation bar, token colours
   ● USDT 99.5%   ● TRX 0.5%
 ┌──────────────────────────────────┐
 │ ₮  USDT    ╱╲_╱‾╲_    2,481.35  │  symbol, price + 24h %
 │    $1.0002 +0.01%      $2,481.84│  sparkline (7d, coloured by 7d direction)
 ├──────────────────────────────────┤
 │ ▼  TRX     _╱‾╲╱‾     48.20     │
 │    $0.2431 +2.37%      $11.72   │
 └──────────────────────────────────┘
   Sort ▾ Value                Prices from CoinGecko, in US dollars · updated 2 min ago
```
- Portfolio total is the sum of `holding.usdValue(price)` (USDT counts at $1 when there's no price). The
  24h change is Σvalue − Σ(value / (1 + change24h/100)), and the percentage is relative to the
  yesterday total. Hidden when no prices are in.
- The eye toggles the shared `hideBalance` (same key as home and widget). When hidden, amounts, values,
  total and change show `••••`, and the allocation bar is grey.
- Sort menu: Value (default), Name, 24h change, persisted with `@AppStorage`.
- Pull-to-refresh refreshes balances and markets. The footer shows the source and how old the data is.
- Search with no match shows `ContentUnavailableView.search`. While searching, the portfolio header is
  hidden.
- Rows push `CoinDetailView` (NavigationLink value `TokenKind`). Each row is one VoiceOver element:
  "USDT, 2,481.35, about $2,481.84, price $1.0002, up 0.01% today".

### Coin screen (`CoinDetailView`)
```
  ‹ Currencies          Tether USD
        ₮  2,481.35 USDT
           ≈ $2,481.84
   [ ↗ Send ]  [ ↙ Receive ]          TRX: [ + Add TRX ] [ ⓘ About fees ]
   $1.0002   +0.01%  · 7D             scrubbing replaces this with the point's price + date
   ╭─────────────────────────────╮
   │      ╱╲    ╱╲_╱‾             │  Swift Charts line + area, accentText or token colour,
   ╰─────────────────────────────╯  hidden y grid, x labels minimal
   [1D] [7D] [1M] [3M] [1Y]         same picker style as Activity's TimeframePicker
   Your position
     Amount 2,481.35 USDT · Value $2,481.84 · Today +$0.25 · Share of portfolio 99.5%
   Market
     Market cap · 24h volume · 24h high / low · All-time high (date)
   USDT: Recent transfers (last 5 from activity.transfers, TransferRow) → "See all in Activity"
   TRX:  Network fuel: transfers left, fees paid all-time (Σ activity.fees), → NetworkFeeInfoView
```
- The price change shown is for the selected range (first vs last point). 24h when the range is 1D.
- Scrubbing shows the nearest point's price and date with a rule mark and a selection haptic. The price
  isn't private, so scrubbing works with balances hidden. Position values still mask.
- The chart range is per screen (`@State`, default 7D). When the range changes, keep the previous
  series dimmed until the new one arrives (no layout jump).
- "See all in Activity" sets `app.selectedTab = .activity`. Tapping a transfer opens the existing
  transfer detail sheet.
- The TRX screen keeps today's explanation text and the fee screen link. The fuel level uses the same
  `transfersLeft` and `FuelLevel` logic as home (move it to a shared helper).

### Home and other entry points
- Home Currencies card: the USDT row pushes the USDT coin screen (instead of switching to Activity).
  The TRX row pushes the TRX coin screen (instead of `NetworkFeeInfoView`). `HomeRoute` gains
  `coin(TokenKind)`, and the zoom source stays on the rows.
- DEBUG `-route`: `search` → `currencies`, plus `coin-usdt`, `coin-trx`.
- Demo mode (`-demo`): deterministic sample `MarketQuote`s and chart series for every range, no network.

### States
- Loading the first prices: the row shows the name instead of the price, the sparkline is a
  placeholder, and the header shows the total with USDT at $1 and no change line.
- Offline or failed: the last data stays. With nothing to show, holdings show without prices and the
  footer says "Prices unavailable".
- Dark and light mode, Dynamic Type up to AX sizes (rows stack, sparkline hides at AX sizes), iPad
  `readableWidth()`, Reduce Motion.

## Constraints
- Theme tokens only (`Theme.Palette`, `Theme.Radius`, `Theme.Typography`). Strings localisable.
- Nothing under `Kestrel/Crypto/`, `SecureStore.swift` or `TronClient+Send.swift` changes.
- `Kestrel/Shared/` stays widget-safe. Nothing new goes there.
- New files are picked up by XcodeGen's folder sources: run `xcodegen generate` and commit the project.

## Tests
- `MarketTests`: parse `coins/markets` and `market_chart` fixtures, portfolio total and 24h change maths
  (including a missing price and zero holdings), allocation shares, sort order, and range change.
- Build and test commands from AGENTS.md pass. Screenshots in dark and light with `-demo` of the tab,
  both coin screens, search, hidden balance and AX type.

## Left to the builder
Exact spacing and typography within the tokens, chart styling details, how the cache is structured,
fixture contents, and the exact wording of hints.

## Update (same day)
Roman moved Currencies out of the tab bar: the tab bar is Wallet + Activity, and Currencies is a full page pushed from the home Currencies card (`HomeRoute.currencies`). Every pushed screen hides the tab bar, so Receive gets normal bottom Copy/Share buttons.
