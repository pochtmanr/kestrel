# Security and custody model: Kestrel Wallet (iOS)

Scope: the iOS code in this repo. References point to files. Read the code for the exact lines.

## 1. Custody model

The wallet is self-custody. A 12-word BIP-39 phrase is generated on the device. It's the only secret that
controls funds, and it is kept in the iOS Keychain in two forms, neither of which opening the app can read:

- **Encrypted under the app PIN** (always). The right PIN is the one that decrypts it; no PIN hash is stored.
- **Behind the current Face ID / Touch ID enrolment** (when biometrics are on), as a Keychain item with
  `.biometryCurrentSet` access control. iOS releases it, and drops it if a face or finger is added.

The private key is re-derived from the phrase when a transfer is signed and is never stored. The address is
stored on its own, so launching the app and reading balances need neither the PIN nor the phrase. TronGrid
builds transactions, the device verifies and signs them, and TronGrid broadcasts them. No server ever
receives the phrase or the private key. The Supabase backend (`Services/Backend.swift`) exists only for
optional features, and the wallet doesn't depend on it.

## 2. Key generation and derivation (`Kestrel/Crypto/`)

| Item | Implementation |
|---|---|
| Entropy | 16 bytes from `SecRandomCopyBytes`. A failure throws |
| Phrase | BIP-39 English, 12 words, SHA-256 checksum. The wordlist is `Resources/bip39-english.txt` (2048 words or it throws) |
| Restore | Accepts 12/15/18/21/24 words, verifies the checksum, normalises the input |
| Seed | PBKDF2-HMAC-SHA512, 2048 rounds, salt `"mnemonic"` (no passphrase), NFKD |
| Master key | HMAC-SHA512 with key `"Bitcoin seed"` (BIP-32) |
| Path | `m/44'/195'/0'/0/0` (TRON): one account, one address |
| Address | Keccak-256 of the uncompressed public key, last 20 bytes, prefix `0x41`, Base58Check |

`KestrelTests/vectors.json` pins seed, key, address and signature for two phrases (checked against
`@scure/bip39` and `@scure/bip32`).

## 3. Storage on the device

Keychain (`Services/SecureStore.swift`): service `com.simnetiq.kestrel`, class generic password,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (not in backups to other devices, not synced to iCloud).
Unit tests use a service of their own, so they never touch a wallet saved on the simulator.

| Account | Content |
|---|---|
| `wallet.phrase.sealed` | The phrase, AES-256-GCM under a key from PBKDF2-HMAC-SHA256 (600,000 rounds, 16-byte salt) of the PIN |
| `wallet.phrase.biometric` | The phrase, behind `SecAccessControl` `.biometryCurrentSet` (`WhenPasscodeSetThisDeviceOnly`). Only while biometrics are on |
| `wallet.address` | The TRON address |
| `wallet.mnemonic` | The phrase in the clear, only between creating a wallet and creating its PIN |
| `security.pin.attempts` | Wrong-PIN count and the time of the last one |
| `support.contact.id` | `kestrel-<uuid>`: an anonymous support-chat id |

Wallets saved by earlier builds (`wallet.mnemonic` for good, `security.pin.v2`, `security.biometric.enabled`)
are moved to this layout the first time the PIN is entered. The plain copy is deleted only after the
encrypted one has been written and read back.

App Group defaults (`Shared/SharedWallet.swift`): the address, USDT and TRX balances, a timestamp, and
the hide-balance flag, for the widget. Standard defaults hold per-transfer notes, the receive-address
nickname and the appearance choice. No keys or phrase go into defaults.

## 4. PIN, biometrics, app lock

- A 6-digit PIN. It isn't stored: it decrypts the phrase. A 6-digit PIN has a million values, so against
  someone who has extracted the Keychain item the protection is the key-derivation cost, not secrecy.
- Wrong PINs are counted in the Keychain, before the check runs, for every PIN prompt (lock screen, send,
  phrase, change PIN). Four are free; then the wait is 1, 5 and 15 minutes, then an hour each time. The
  count survives a relaunch, and setting the clock back doesn't shorten the wait.
- Biometrics: `LAContext` (`deviceOwnerAuthenticationWithBiometrics`), then the phrase is read from the
  biometry-bound item with that context. Unlocking, sending and showing the phrase all depend on that read.
- Changing the PIN needs the current PIN (never biometrics). The old record stays until the new one is written.
- Turning biometrics on needs the PIN.
- The app locks on every trip to the background. A separate window (`App/PrivacyCurtain.swift`) covers the
  app, sheets included, in the app switcher.
- The recovery words are hidden while the screen is recorded or mirrored, and a screenshot of them gets a
  warning. Third-party keyboards are disabled app-wide.
- Copies to the clipboard are local-only (no Universal Clipboard) and expire.

## 5. Signing

- libsecp256k1 (`swift-secp256k1` 0.23.2), context randomised at start. RFC 6979 nonces, low-S, recoverable.
- USDT send (`Services/TronClient+Send.swift`): TronGrid builds the transaction. Before signing,
  `Crypto/TransferVerifier.swift` decodes `raw_data_hex` and requires `SHA256(raw_data) == txID`, exactly one
  `TriggerSmartContract`, our address as owner, the USDT contract, `transfer(address,uint256)` with the
  confirmed recipient and amount, no TRX or token value attached, the expected `fee_limit`, and an expiry
  within the hour. Unknown or repeated fields fail the check. The device signs the digest it computed.
- History (`Features/Send/AddressSafety.swift`): zero-value transfers are dropped, transfers under 1 USDT
  can't be repeated or have their address copied, and the review screen warns about a first-time recipient
  and about one that looks like an address from the history.

## 6. What leaves the device

| Destination | Data |
|---|---|
| `api.trongrid.io` | The wallet address (reads), signed transactions, and the IP address. The widget also reads about every 15 minutes. A TronGrid project key (quota only, public by design); a request the key is refused for is retried without it |
| `api.trongrid.io` (fee estimate) | When a valid recipient is entered on Send, before the user confirms: the wallet address, the recipient address and the amount, in a read-only simulation of the transfer |
| `api.coingecko.com` | Coin ids (`tether`, `tron`) and the IP address. Never the wallet address or a balance |
| `api.kraken.com` | The pair names `TRXUSD` / `USDTUSD` for the 5-year chart, and the IP address. Never the wallet address or a balance |
| `supabase.holylabs.net` | Only what a backend feature sends (none ship yet). The public anon key; no user session today |
| Support chat (Chatwoot, once configured) | The anonymous support id, the app name, and whatever the user types. Loads the Chatwoot JS SDK into a `WKWebView` |
| `tronscan.org`, terms and privacy pages | Only when the user taps |

Never sent: the phrase, seed, private key or PIN. There's no analytics or crash-reporting
SDK, no certificate pinning, and default ATS applies.

## 7. Known risks (backlog, roughly by severity)

1. **No certificate pinning** for TronGrid. With transactions verified before signing, an interceptor can
   show wrong balances and history or block sends, but can't change what is signed.
2. **Keychain survives a reinstall.** The wallet reappears (still behind its PIN). Decide a first-launch
   policy; a prompt that offers to wipe is itself a way to lose funds.
3. **No wipe after repeated wrong PINs.** The wait tops out at an hour per attempt.
4. **The recovery phrase can be copied** to the clipboard (local-only, 60 seconds).
5. **One TronGrid key in a public repo.** It falls back to keyless requests, which have a low per-IP limit.
   Restrict the key in the TronGrid dashboard; consider a second provider.
6. **Support chat** (not yet switched on): navigation is limited to the Chatwoot origin, but the chat
   content itself is third-party JavaScript.
7. **Test coverage.** The send path is covered up to the signature (`TransferVerifierTests`); broadcasting
   and the biometric prompt aren't exercised by tests.
