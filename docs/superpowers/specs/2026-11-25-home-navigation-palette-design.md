# Kestrel: single-stack home, zoom cards, "Slate & Ember" palette

## Context
The home screen says the same thing three times. A row of 4 small buttons (Receive/Send/History/Copy)
repeats the big tiles below it, the Receive tab, and tap-to-copy in the header. The app also leans on a
tab bar (Wallet/Receive/Settings) and sheets. Roman wants one screen as the hub, real full screens
instead of bottom sheets, and a blue-grey + orange look that's premium and Apple-grade.

Decided with Roman:
- Delete the 4 small action buttons. Keep only big cards.
- Hub model: **zoom cards**. Each big card grows into its own full screen (iOS 18 zoom transition, plain
  push/cover on iOS 17).
- **No tab bar.** One `NavigationStack`.
- Mood: **Slate & Ember, dark-first** (light mode still done properly).
- Settings and Support: **glass glyphs top-right** in the header.
- Material: **Liquid Glass for chrome only** (header glyphs, floating controls) on iOS 26. Cards are solid
  slate. iOS 17–25 get solid or material fallbacks.
- Scope this round: **home + navigation + palette**. Fonts, the bird icon and onboarding come in a later round.

Anti-goals: a cluttered home, orange everywhere (it's one hot spot), low-contrast amounts, any change to
security behaviour, or touching crypto/signing code.

## Target home
```
 ◉ Main wallet            (ⓘ)(⚙)     glass glyphs: support (if configured), settings
   TQx…9fA ⧉                          tap = copy (haptic + "Copied")
           Total balance 👁
           12,480.50 $                hero, tap toggles hide (keeps widget sync)
 ┌─────────────┐ ┌─────────────┐
 │ ↗  Send     │ │ ⬇  Receive  │      Send = the only ember-filled surface
 └─────────────┘ └─────────────┘
 ┌──────────────────────────────┐
 │ Activity        ↗ −120 · 2h  │      last transfer + 7-day bars → full Activity
 │ ▁▂▅▃▇▂▁                      │      empty state: "No activity yet"
 └──────────────────────────────┘
 ┌──────────────────────────────┐
 │ ◆ Network fuel  38 TRX  ≈2 ●│      TRX for fees; ● ok / amber low / red empty
 └──────────────────────────────┘      → NetworkFeeInfoView
```
The USDT/TRX asset stack is removed: the balance *is* USDT, and TRX lives in the fuel card.

## Navigation map
| From home | Opens as | Why |
|---|---|---|
| Send card | `fullScreenCover` + zoom from card | It's a modal task with Cancel. Keeps SendView's own stack, review/PIN sheets and `dismiss()` exactly as they are |
| Receive card | push + zoom | DepositView without its outer `NavigationStack` |
| Activity card | push + zoom | `AllActivityView`; transfer detail stays a sheet (short look-up) |
| Fuel card | push + zoom | `NetworkFeeInfoView` |
| ⚙ glyph | push | SettingsView without its outer `NavigationStack`; recovery-phrase sheet unchanged |
| ⓘ glyph | sheet (unchanged) | SupportChatSheet |
| Transfer detail → Repeat | Send cover, prefilled | Same delay pattern as today |

Routes become a typed enum (`HomeRoute: Hashable { receive, activity, fees, settings }`) instead of the
`String` routes and `AppModel.Tab`.

## Palette (Theme.Palette + asset catalogs; dark / light)
| Token | Dark | Light | Use |
|---|---|---|---|
| background | #0E131A | #EEF1F5 | screen |
| surface | #18202A | #FFFFFF | cards |
| surfaceRaised | #222B37 | #F5F7FA | pressed / nested |
| separator | white 8% | slate 10% | hairlines |
| textPrimary / Secondary / Tertiary | #EDF1F5 / #9AA5B3 / #6A7584 | #111821 / #4F5A68 / #8792A0 | text tiers |
| accent (ember fill) | #F26B1F | #E2601A | Send card, primary buttons, the bird |
| accentText | #FF8B4A | #B4470F | orange text/links (AA ≥ 4.5) |
| positive | #3DCC80 | #1B8A52 | money in, success |
| danger | #FF5D5D | #D23B3B | errors, empty fuel |
| warning / pending | #F5B53D | #B97A00 | low fuel, confirming |
| usdt / trx | unchanged | unchanged | token icons |

**Money out is no longer orange.** It used `negative = .orange`, which would now clash with the ember
accent. Outgoing items use a neutral slate icon and primary text, and green stays for money in. The
home's top gradient becomes a faint ember glow on slate. Contrast for every text/background pair is
checked to WCAG AA, and the hex values get tuned if a pair fails.

## Implementation steps (commit per step)
1. **Design doc.** Write `docs/superpowers/specs/2026-11-25-home-navigation-palette-design.md` (this
   design) and commit it.
2. **Palette.** Add the colour sets to `Kestrel/Resources/Assets.xcassets` (light/dark). Rewrite
   `Theme.Palette` in `Kestrel/Shared/Theme.swift` to read them (the widget shares this file, so stay
   UIKit-free beyond UIColor). Update `AccentColor` in `Kestrel/Brand/Kestrel.xcassets` and
   `KestrelWidget/Assets.xcassets`, and `Background`/`LaunchBackground`. Replace `negative` usages
   (TransferRow, TransferDetailView, lastActivityTile). Update `Surface` in `Kestrel/UI/Components.swift`
   to the new surface and hairline.
3. **Navigation shell.** In `KestrelApp.swift`, `MainTabView` → `HomeView` root (or WalletView owns the
   stack). Delete `AppModel.Tab`/`selectedTab` (AppModel.swift:22-23, :68) and fix every reference (grep
   `selectedTab`, `.deposit`). Strip the outer `NavigationStack` from `DepositView` and `SettingsView`.
   Move the support overlay into the home header.
4. **Zoom helpers in Components.swift.** `zoomSource(id:ns:)` → `matchedTransitionSource` on iOS 18+, no-op
   before. `zoomDestination(id:ns:)` → `navigationTransition(.zoom…)` on iOS 18+. `GlassGlyph` reuses
   the existing `RoundGlass` logic for ⚙ (generalise `SupportButton`'s circle).
5. **Home.** In `WalletView.swift`, delete `actions`, `HomeAction`, `tiles`, `assets`/`stackEdge`/`AssetRow`.
   Add `HomeCard` (solid surface, radius `Theme.Radius.tile`, press scale, haptic) and four cards: Send
   (ember), Receive, Activity (last transfer + 7-day bars via Swift Charts with hidden axes, net flow
   per day from `app.history`), Fuel (TRX amount, ≈ transfers left = `trxSun / TRX.minimumForTransferSun`,
   status dot from `hasGasForTransfer`). Keep the balance hide, the 15 s refresh loop, pull-to-refresh,
   the detail sheet and repeat-payment exactly as they are.
6. **Polish and a11y.** Every card is one VoiceOver element with a label and hint ("Send USDT", "Activity,
   last: sent 120 USDT 2 hours ago"). Check Dynamic Type up to AX3 (cards stack, text wraps), iPad
   `readableWidth()`, and Reduce Motion (zoom → crossfade, handled by the system). Strings use
   `Text("…")`/`String(localized:)`.
7. **Docs.** Update AGENTS.md (map row: tabs → single stack), `docs/ARCHITECTURE.md` and
   `docs/roadmap/KESTREL_PLAN.md`: tick the redesign IA, and leave fonts, bird and onboarding as next.

Not touched: `Kestrel/Crypto/`, `SecureStore.swift`, `TronClient+Send.swift`, the send logic inside
SendView (only how it's presented), onboarding and PIN.

## Verification
- `xcodegen generate` (only if project.yml changes), then
  `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`
  and `… test` (crypto vectors must pass).
- Install, then run `xcrun simctl launch booted com.simnetiq.kestrel -demo` and take screenshots of the home, each
  card's destination, Send cover, settings, transfer detail, in **dark and light**
  (`xcrun simctl ui booted appearance dark|light`), plus a large Dynamic Type run. Look at every
  screenshot. Check the zoom transition on an iOS 18+ simulator.
- Check the widget still renders with the new palette.
- Report in the terminal with screenshot paths. No web artifacts.
