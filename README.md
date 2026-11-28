# Kestrel Wallet (iOS)

A self-custody USDT wallet on TRON for iPhone and iPad, published by Simnetiq Ltd.
The recovery phrase never leaves the device. There's no account. Balances and transfers go directly to the TRON network
through TronGrid. A Supabase backend (`Kestrel/Services/Backend.swift`) is there for optional features
that need a server.

- SwiftUI, iOS 17+, Swift 6 (strict concurrency)
- One app target (`Kestrel`), one WidgetKit balance widget (`KestrelWidget`), unit tests (`KestrelTests`)
- The only dependency is `swift-secp256k1` (libsecp256k1)

## Build

```bash
brew install xcodegen          # once
xcodegen generate              # after any change to project.yml
open Kestrel.xcodeproj
```

Command line:

```bash
xcodebuild -project Kestrel.xcodeproj -scheme Kestrel \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Kestrel.xcodeproj -scheme Kestrel \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build test
```

DEBUG builds accept a `-demo` launch argument: sample balances and history, no network.
Use it for screenshots.

## Docs

- [AGENTS.md](AGENTS.md): orientation for AI agents and new contributors
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/SECURITY.md](docs/SECURITY.md)
- [docs/roadmap/KESTREL_PLAN.md](docs/roadmap/KESTREL_PLAN.md): what's done and what's next

## Releasing (App Store)

1. `scripts/capture-screenshots.sh`: raw iPhone 6.9" and iPad 13" shots from the simulators (`-demo` wallet).
   iPhone Duo (unfold it in Xcode first: `scripts/capture-screenshots.sh duo`) and the widget slide are by hand.
2. `cd fastlane/screenshot-studio && node server.mjs`: edit headlines, then export and run `scripts/collect.sh`
   (see its README).
3. Listing text lives in `fastlane/metadata/<locale>/`. Uploads: see `fastlane/README.md` (needs the
   App Store Connect API key in `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_FILEPATH`, and `ASC_APP_VERSION`).
