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
- [x] `Localizable.xcstrings` (English) with `SWIFT_EMIT_LOC_STRINGS`. Custom view titles take `LocalizedStringKey`.
- [x] Support: Chatwoot placeholders in `SupportConfig`. The support button and legal rows stay hidden until they're set.
- [x] The DEBUG `-demo` launch argument loads sample data for screenshots.
- [x] Build green, crypto vector tests pass.
- [x] Backend client (`Kestrel/Services/Backend.swift`): the same Supabase project and anon key as the source app, for wallet features that need a server. No card endpoints.

## Done (2026-11-25): Activity tab
- [x] Full USDT history cached on device (`ActivityStore`), paged from TronGrid on demand. No server.
- [x] Balance and flow charts with 7D / 1M / 3M / 1Y / All and drag-to-scrub; insight tiles (in, out, net, fees, count, largest) and top counterparties.
- [x] Search (address, amount, tx id) and filters (direction, amount range, dates, counterparty); network fee per sent transfer.

## Next
1. **Support:** stand up the Simnetiq Chatwoot instance and fill in `SupportConfig.chatwootBaseURL` and `chatwootWebsiteToken`.
2. **Support and privacy pages:** decide where they live (a simple static page on the app's own domain), then set `SupportConfig.terms` and `privacy`.
3. **Launch features.** Pick from:
   - an address book with labels
   - price and fiat value display
   - payment request links and QR codes with an amount
   - a better first-run backup check (re-enter words)
   - a CSV transaction export
   - TRX staking for energy
   - multiple wallets
   - a watch-only address
   - more TRC-20 tokens
   - push notifications for incoming transfers (needs a server or a third-party service)
4. **Redesign** (prompt: `docs/roadmap/NEXT_SESSION_DESIGN.md`): a new information architecture (don't copy the current tab and home layout), then the final icon and brand assets. Most of it is token and component work now.
5. **Security backlog:** see `docs/SECURITY.md` §7. Verify the txID before signing, persist the PIN throttle, and fix the privacy manifest reason code before submission.

## QA
- Unit: the existing crypto vectors. Add send and fee edge cases, URI parsing and PIN lockout.
- UI flows on simulator and device: create, restore, PIN, Face ID, send (testnet or a small mainnet amount), receive, widgets, erase.
- Review pass: accessibility, Dynamic Type, dark mode, iPad layouts.
- `xcrun simctl io booted screenshot` works with `-demo` for quick screenshots.

## App Store submission
- Metadata says what it is: a self-custody USDT/TRON wallet. Simnetiq doesn't hold funds. No exchange, card or fiat.
- Review notes: self-custody, keys in the device Keychain, no account or server. Test path: create a wallet (sending needs TRX for fees).
- Required URLs: support and privacy policy.
- App Privacy labels: collects almost nothing. Confirm what the Chatwoot support chat collects.
- Export compliance: `ITSAppUsesNonExemptEncryption: false` is set. Re-check it after any new crypto.
- Screenshots: new ones, from the redesigned app.
