---
title: About
description: What {{appName}} is, what it is not, how it works, and who publishes it.
---

{{appName}} is a self-custody wallet for USDT on the TRON network. It runs on iPhone and iPad with iOS 17 or later, in English, Russian and Chinese.

## What it does

- **Holds** USDT (TRC-20) and TRX, the coin that pays TRON network fees.
- **Sends** USDT to a TRON address that you paste or scan from a QR code. A review screen shows the recipient, the amount and the estimated network fee before you confirm.
- **Receives** USDT at your own TRON address, shown as text and as a QR code.
- **Keeps a history** of your transfers, with a note or a name for an address if you add one.
- **Shows your balance in a widget** on the Home Screen and the Lock Screen.
- **Shows market prices and charts** for USDT and TRX, for information only.
- **Sends price alerts** that you set yourself. They are checked on your device and delivered as local notifications.

## What it is not

{{brand}} is wallet software and nothing more.

- No card and no way to pay for crypto with money.
- No exchange or swap between cryptoassets.
- No account, no sign-up and no identity checks.
- No networks other than TRON.
- No custody. {{company}} never holds your keys or funds, and cannot move, freeze or recover them.

It is also not financial advice. Please read the [risk disclosure](/risks/) before you use the app.

## How it works

**Your keys stay on your device.** The recovery phrase is created on your iPhone or iPad and stored in the iOS Keychain. It is not synced to iCloud and is never sent to us. Transfers are signed on the device. More detail is on the [security page](/security/).

**We currently charge no fee.** The only cost of a transfer is the TRON network fee, about {{networkFee}} for a USDT transfer. It is paid in TRX from your wallet to the network, not to us. If we ever introduce a fee, we will announce it in the app and on this site before it applies. See the [terms of use](/terms/).

**The app contacts few services, and says which.** Requests go directly from your device to:

- **TronGrid**, which receives your public wallet address and the transfers you have signed, to read your balance and history, estimate fees and broadcast transfers;
- **CoinGecko**, which receives the names of the coins, to show prices and charts;
- **Kraken**, which receives the names of the coins, to show long-range price charts.

CoinGecko and Kraken never receive your wallet address. Each service also sees your IP address, as any service on the internet does. The app contains no analytics, advertising or tracking code. The [privacy policy](/privacy/) has the full list.

**This website is static.** It sets no cookies, uses no analytics and loads nothing from third parties.

## Who publishes it

{{appName}} is published by {{company}}, a company registered in {{registeredIn}} with company number {{companyNumber}}. Its registered office is {{registeredOffice}}.

{{company}} publishes software. It is not a bank, exchange or custodian, and is not authorised or regulated by the Financial Conduct Authority. Full company details and regulatory status are in the [legal notice](/legal/).

## Get in touch

- For help with the app, see [support](/support/) or email [{{supportEmail}}](mailto:{{supportEmail}}).
- To report a vulnerability, see the [security page](/security/).
- For questions about your data, email [{{privacyEmail}}](mailto:{{privacyEmail}}).

We will never ask for your recovery phrase or PIN.
