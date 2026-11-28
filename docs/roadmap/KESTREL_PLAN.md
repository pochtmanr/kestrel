# Kestrel Wallet: plan and progress

| | |
|---|---|
| Product | **Wallet only**: a self-custody USDT (TRON) wallet. No card, no fiat top-ups, no KYC |
| Publisher | **Simnetiq Ltd**, its own App Store **organization** account (guideline 3.1.5) |
| Audience | International, English UI at launch |
| Name | **Kestrel** in code, **Kestrel Wallet** on the App Store (chosen 2026-11-25). Nearby names exist: "Kestrl – Ethical Finance" (Kestrl LTD) and a Solana DeFi product called Kestrel. **Run a trademark search before submission** |
| IDs | `com.simnetiq.kestrel` (+ `.widget`, `.tests`), app group `group.com.simnetiq.kestrel`, URL scheme `kestrel`, team `F7YY9U667A` |
| Version | 1.0.0 (1) |

## Done (2026-11-25): foundation
- [x] Forked with history into `/Volumes/RomanSSD/kestrel-wallet-ios`. **No git remote yet:** add one.
- [x] Card stack removed entirely: screens, services, card tab, home card tile, backend links, card-payment and KYC return links.
- [x] Every identifier renamed: targets, folders, bundle IDs, Keychain service, widget kind, support-id prefix, display name, Face ID and camera texts. The old React Native Keychain migration is deleted.
- [x] Placeholder brand: a rust/amber wing icon and logos, accent `#C25A1F`. To be replaced by the redesign.
- [x] Theme token layer: `Kestrel/Shared/Theme.swift` (palette, radius, spacing, amount typography). Views use the tokens.
- [x] `Localizable.xcstrings` (English, Russian, Simplified Chinese) with `SWIFT_EMIT_LOC_STRINGS`. Custom view titles take
  `LocalizedStringKey`; strings built in code use `tr()`. Language, theme and text size are chosen in Settings.
- [x] Support: Chatwoot placeholders in `SupportConfig`. The support chat button stays hidden until they're set. The legal rows link to kastrel.xyz.
- [x] The DEBUG `-demo` launch argument loads sample data for screenshots.
- [x] Build green, crypto vector tests pass.
- [x] Backend client (`Kestrel/Services/Backend.swift`): the same Supabase project and anon key as the source app, for wallet features that need a server. No card endpoints.

## Done (2026-11-25): Activity tab
- [x] Full USDT history cached on device (`ActivityStore`), paged from TronGrid on demand. No server.
- [x] Balance and flow charts with 7D / 1M / 3M / 1Y / All and drag-to-scrub; insight tiles (in, out, net, fees, count, largest) and top counterparties.
- [x] Search (address, amount, tx id) and filters (direction, amount range, dates, counterparty); network fee per sent transfer.

## Done (2026-11-25): Currencies screen
- [x] A Currencies screen, pushed from the home Currencies card (the old search tab is gone; the tab bar is Wallet + Activity): portfolio value with 24h change, allocation bar, coin list with 7-day sparklines, sort and in-tab search.
- [x] Coin screen: price chart 1D–1Y with scrubbing, your position, market stats (cap, volume, 24h range, ATH), recent USDT transfers or TRX fuel and fees paid.
- [x] Home Currencies rows open the coin screens. `TokenKind` is now the coin registry: a new coin is a new case.

## Done (2026-11-27): charts, alerts, live fees, Activity and Receive rework
- [x] Coin screen: 5-year range (Kraken weekly candles), expandable full-screen chart with volume bars and high/low markers, a returns table (1D–5Y), more market stats.
- [x] Price alerts, phase 1: on-device, local notifications, checked while the app is open and at iOS's discretion in the background (alerts can arrive late).
- [x] Live network-fee estimate per recipient on Send (read-only simulation); the fixed "13–14 TRX" text is gone. About 7 TRX to an address that holds USDT, 13–14 to one that doesn't.
- [x] Activity: app-styled day cards, inline search above the transfers, an iPad layout built on `AdaptiveColumns`.
- [x] Receive: Copy and Share under the address; the "Live receiver" redesign (listening halo, request headline, receipt moment, show/hide details).

## Next
1. **Support:** stand up the Simnetiq Chatwoot instance and fill in `SupportConfig.chatwootBaseURL` and `chatwootWebsiteToken`.
2. **Support and privacy pages:** done. They live in `website/` (kastrel.xyz), and `SupportConfig.terms`, `privacy` and `support` point at them.
3. **Launch features.** Pick from:
   - an address book with labels
   - price and fiat value display
   - payment request links and QR codes with an amount
   - a better first-run backup check (re-enter words)
   - a CSV transaction export
   - TRX staking for energy
   - multiple wallets
   - a watch-only address
   - more TRC-20 tokens (the Currencies tab is ready: add a `TokenKind` case and a balance source)
   - push notifications for incoming transfers (needs a server or a third-party service)
   - price alerts, phase 2: reliable delivery by push (APNs key, Push capability, a Supabase table keyed by an anonymous install id, a scheduled function)
   - landscape for the expanded chart (needs rotation enabled app-wide and every other screen locked to portrait)
4. **Redesign** (prompt: `docs/roadmap/NEXT_SESSION_DESIGN.md`): a new information architecture (don't copy the current tab and home layout), then the final icon and brand assets. Most of it is token and component work now.
5. **Security backlog:** see `docs/SECURITY.md` §7. Verify the txID before signing, persist the PIN throttle, and fix the privacy manifest reason code before submission.

## QA
- Unit: the existing crypto vectors. Add send and fee edge cases, URI parsing and PIN lockout.
- UI flows on simulator and device: create, restore, PIN, Face ID, send (testnet or a small mainnet amount), receive, widgets, erase.
- Review pass: accessibility, Dynamic Type, dark mode.
- [x] iPad and unfolded-iPhone layouts: the system's adaptable tab bar (`SidebarTabShell`; `MainSplitView` on iOS 17), two-column Wallet, Activity,
  Currencies, coin and Receive screens, form-sized sheets, rotating QR camera, large widget.
- Verify the iPhone Duo's inner display by hand (the simulator can't be unfolded from simctl).
- `xcrun simctl io booted screenshot` works with `-demo` for quick screenshots.

## App Store submission
- Metadata says what it is: a self-custody USDT/TRON wallet. Simnetiq doesn't hold funds. No exchange, card or fiat.
- Review notes: self-custody, keys in the device Keychain, no account or server. Test path: create a wallet (sending needs TRX for fees).
- Required URLs: support and privacy policy.
- App Privacy labels: collects almost nothing. Confirm what the Chatwoot support chat collects.
- Export compliance: `ITSAppUsesNonExemptEncryption: false` is set. Re-check it after any new crypto.
- Screenshots: `scripts/capture-screenshots.sh`, then `fastlane/screenshot-studio` (see its README).
  iPhone 6.9" and iPad 13" are automated; iPhone Duo and the widget slide are captured by hand.
- Listing: `fastlane/metadata/en-US/` (English at launch). Support and privacy URLs point at kastrel.xyz.
