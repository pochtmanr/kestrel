---
title: Security
description: How {{appName}} protects your keys, and how to report a vulnerability.
---

## How the app protects your wallet

- **Keys stay on the device.** The recovery phrase is created on your iPhone or iPad and stored in the iOS Keychain. It is restricted to that device, is not synced to iCloud, and is readable only while the device is unlocked.
- **Signing happens locally.** Transfers are signed on the device. Only the signed transaction is sent to the network.
- **The app locks.** A 6-digit PIN, with optional Face ID, protects the app. The PIN is stored only as a salted hash. The app locks when it goes to the background and hides its content in the app switcher.
- **Nothing to breach on our side.** There are no accounts and we run no server that stores wallets, keys or balances.
- **No third-party tracking code.** The app contains no analytics or advertising software.

No software is free of faults. See the [risk disclosure](/risks/).

## Keeping yourself safe

- Write your recovery phrase on paper and keep it offline. Never photograph it or type it into a website.
- Check the full address before every transfer.
- Keep iOS and the app up to date, and use a device passcode.
- We will never ask for your recovery phrase or PIN.

## Reporting a vulnerability

If you have found a security problem in the app or this website, please tell us privately at **[{{securityEmail}}](mailto:{{securityEmail}})**.

Please include:

- what the problem is and what an attacker could do with it;
- the steps to reproduce it, with the app and iOS version;
- any proof-of-concept code or screenshots.

**What we ask**

- Give us reasonable time to fix the problem before you make it public.
- Test only with your own wallets and devices. Do not access or move other people's funds or data.
- Do not use social engineering, physical attacks or denial-of-service attacks.

**What you can expect**

- We will confirm that we received your report within five working days.
- We will keep you informed while we investigate and fix it.
- We will not take legal action against you for research carried out in good faith and within these rules.
- With your permission, we will credit you once the problem is fixed.

We do not currently run a paid bug bounty programme.

## In scope

- The {{appName}} iOS app and its widget
- The website kastrel.xyz

## Out of scope

- The TRON network, USDT, and third-party services such as TronGrid, CoinGecko and Kraken (please report those to their operators)
- Attacks that need a jailbroken device or physical access to an unlocked device
- Reports from automated scanners with no demonstrated impact
