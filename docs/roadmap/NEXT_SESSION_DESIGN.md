# Next session: brand and first screens

Paste this into a new conversation started in `/Volumes/RomanSSD/kestrel-wallet-ios`:

---

Read `AGENTS.md`, `docs/roadmap/KESTREL_PLAN.md` and `docs/ARCHITECTURE.md` first.

We're giving **Kestrel Wallet** (a self-custody USDT-on-TRON wallet for iOS, published by Simnetiq Ltd) its own
look. The foundation is done: the card code is gone, everything is renamed, there's a theme token layer, and
the brand is a placeholder (a rust/amber wing icon, accent `#C25A1F`). This session covers five things, in order:

1. **Fonts.** Pick a type system: a display face for balances and headings, and a text face (or SF Pro).
   Use only fonts we can ship (SIL OFL or similar; record the licence in the repo). Bundle them under
   `Kestrel/Resources/Fonts/`, register them with `UIAppFonts` in `project.yml` (the widget too, if it uses
   them), and expose them through `Theme.Typography`. Fonts must support Dynamic Type (`Font.custom(_:size:relativeTo:)`).
2. **Colours.** A full palette in `Theme.Palette` and the asset catalogs: accent, background, surface,
   text tiers, positive/negative/warning, and the USDT/TRX token colours, with light **and** dark variants.
   Check contrast (WCAG AA for text). Update `AccentColor` in `Kestrel/Brand/Kestrel.xcassets` and
   `KestrelWidget/Assets.xcassets`, and `Background`/`LaunchBackground` in `Kestrel/Resources/Assets.xcassets`.
3. **The bird.** A kestrel mark for the app icon, logo, launch logo and the settings glyph. It has to be
   original, simple, legible at 20 pt (widget) and work as an iOS 18 tinted/dark icon. Draw it as vector
   (SwiftUI `Shape` or SVG → PNG at the sizes in the asset catalogs). Replace every image in
   `Kestrel.xcassets` (AppIcon light/dark/tinted 1024², Logo, LaunchLogo, LogoGlyph) and the widget `Logo`.
4. **Welcome screens.** Redesign onboarding (`Kestrel/Features/Onboarding/OnboardingViews.swift`):
   the welcome screen, create, restore and backup. Keep the security behaviour exactly as it is (phrase
   generation, backup warning, clipboard expiry, PIN setup next). Consider a short paged intro
   (self-custody, security, TRON fees) before "Create / Restore".
5. **Home layout.** Redesign the wallet home (`Kestrel/Features/Wallet/WalletView.swift`): the balance
   header, actions (Receive, Send, History, Copy), tiles and the asset list. Don't copy the current layout;
   propose a new information architecture for the home screen and tab bar (now: Wallet, Receive,
   Settings).

How to work:
- Start by asking me about the brand direction (mood, references, light or dark first, playful or serious)
  and show 2–3 options for fonts, palette and bird *before* building. Use ASCII mockups or local
  HTML/PNG files with their paths. **Don't publish web artifacts.**
- Go through `Theme` tokens and `Kestrel/UI/Components.swift`, not literals in views.
- Keep strings localisable (`Text("…")`, `LocalizedStringKey`, `String(localized:)`). English only for now.
- Dark mode, Dynamic Type, VoiceOver labels and iPad width (`readableWidth()`) must all work.
- Verify on the simulator: build with `-derivedDataPath build`, install, then
  `xcrun simctl launch booted com.simnetiq.kestrel -demo` (sample data) and
  `xcrun simctl io booted screenshot <file>`. Check light and dark, and look at every screenshot.
- Both `xcodebuild … build` and `xcodebuild … test` must pass. Commit in logical steps (fonts, palette,
  icon, onboarding, home) and update `docs/roadmap/KESTREL_PLAN.md`.

Out of scope this session: new features (address book, fiat prices, …), the backend
(`Kestrel/Services/Backend.swift` exists but is unused), support chat config, and the App Store listing.

---

## Reference: where things are now

| Area | File |
|---|---|
| Tokens (palette, radius, spacing, amount font) | `Kestrel/Shared/Theme.swift` |
| Buttons, surfaces, rows, QR code, support button | `Kestrel/UI/Components.swift` |
| Onboarding (welcome, create, restore, backup) | `Kestrel/Features/Onboarding/OnboardingViews.swift` |
| PIN setup and lock screen | `Kestrel/Features/Lock/PinViews.swift` |
| Home, activity, transfer detail | `Kestrel/Features/Wallet/WalletView.swift` |
| Tabs, root stage switch, app-switcher cover | `Kestrel/App/KestrelApp.swift` |
| App icon, logos, accent | `Kestrel/Brand/Kestrel.xcassets` |
| Background colours | `Kestrel/Resources/Assets.xcassets` |
| Widget look | `KestrelWidget/BalanceWidget.swift`, `KestrelWidget/Assets.xcassets` |
