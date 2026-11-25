# Security and custody model: Kestrel Wallet (iOS)

Scope: the iOS code in this repo. References point to files. Read the code for the exact lines.

## 1. Custody model

The wallet is self-custody. A 12-word BIP-39 phrase is generated on the device and stored as UTF-8 in the
iOS Keychain. It's the only secret that controls funds. The private key is re-derived from the phrase
whenever it's needed (address lookup, signing) and is never stored. TronGrid builds transactions, the
device signs them, and TronGrid broadcasts them. The PIN and Face ID gate the UI. They don't encrypt or
wrap the phrase. No server ever receives the phrase or the private key. The Supabase backend (`Services/Backend.swift`)
exists only for optional features, and the wallet doesn't depend on it.

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
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (not in backups to other devices, not synced to iCloud), no
`SecAccessControl`.

| Account | Content |
|---|---|
| `wallet.mnemonic` | The recovery phrase |
| `security.pin.v2` | `hex(salt16) + ":" + hex(SHA256(salt ‖ pin))` |
| `security.biometric.enabled` | `"1"` when biometrics are on |
| `support.contact.id` | `kestrel-<uuid>`: an anonymous support-chat id |

App Group defaults (`Shared/SharedWallet.swift`): the address, USDT and TRX balances, a timestamp, and
the hide-balance flag, for the widget. Standard defaults hold per-transfer notes, the receive-address
nickname and the appearance choice. No keys or phrase go into defaults.

## 4. PIN, biometrics, app lock

- A 6-digit PIN, stored as salted single-pass SHA-256. The lock screen disables the pad for 30 s after
  every 5th wrong PIN. The counter lives in view state and resets on relaunch.
- Biometrics (`LAContext`, `deviceOwnerAuthenticationWithBiometrics`) return a Bool that gates the UI.
  They aren't bound to a Keychain item.
- The app locks on every trip to the background. An overlay hides balances in the app switcher.
- Copies to the clipboard are local-only (no Universal Clipboard) and expire.

## 5. Signing

- libsecp256k1 (`swift-secp256k1` 0.23.2), context randomised at start. RFC 6979 nonces, low-S, recoverable.
- USDT send (`Services/TronClient+Send.swift`): TronGrid builds the transaction and the app signs the
  returned `txID`. **The app doesn't yet verify `txID == SHA256(raw_data_hex)` or decode `raw_data`**
  (see §7, item 1).

## 6. What leaves the device

| Destination | Data |
|---|---|
| `api.trongrid.io` | The wallet address (reads), signed transactions, and the IP address. The widget also reads about every 15 minutes. No API key |
| `supabase.holylabs.net` | Only what a backend feature sends (none ship yet). The public anon key; no user session today |
| Support chat (Chatwoot, once configured) | The anonymous support id, the app name, and whatever the user types. Loads the Chatwoot JS SDK into a `WKWebView` |
| `tronscan.org`, terms and privacy pages | Only when the user taps |

Never sent: the phrase, seed, private key, PIN or PIN hash. There's no analytics or crash-reporting
SDK, no certificate pinning, and default ATS applies.

## 7. Known risks (backlog, roughly by severity)

1. **Blind signing of TronGrid-built transactions.** Recompute the txID and decode `raw_data` (contract,
   recipient, amount, `fee_limit`) before signing, or build the protobuf locally.
2. **The phrase is protected by the Keychain only.** Consider `SecAccessControl` (`.userPresence`) or a
   Secure Enclave wrapping key.
3. **Weak PIN gate.** The throttle resets on relaunch, `ConfirmWithPINSheet` has no throttle, and you can
   change the PIN without entering the old one. Persist the counters in the Keychain with escalating
   delays.
4. **Biometrics as a Bool** without an `evaluatedPolicyDomainState` check.
5. **No certificate pinning** for TronGrid.
6. **Keychain survives a reinstall.** The wallet and PIN reappear. Decide a first-launch policy.
7. **Erase is incomplete.** Notes, the address nickname and the support id remain.
8. **Privacy manifest.** It declares UserDefaults reason `CA92.1`, but the app and widget share App Group
   defaults, for which Apple's reason is `1C8F.1`. Fix this before submission.
9. **Ignored return codes**: `SecRandomCopyBytes` for the PIN salt and the secp256k1 context seed, and
   `CCKeyDerivationPBKDF`.
10. **Test coverage.** Two derivation vectors, no send tests, and a live network test that depends on a
    third-party address.
