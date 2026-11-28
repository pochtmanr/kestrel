---
title: Help
description: Answers to common questions about {{appName}}: setting up, the recovery phrase, the PIN, transfers, fees and privacy.
---

Short answers to common questions. If yours is not here, see [Support](/support/).

## Getting started

### What is {{appName}}?

A self-custody wallet for USDT on the TRON network. Your keys stay on your device, and {{company}}, the publisher, never holds your funds.

### Which devices does it work on?

iPhone and iPad with iOS 17 or later. The app is in English, Russian and Simplified Chinese.

### Should I create a wallet or restore one?

"Create a new wallet" gives you a new 12-word recovery phrase to write down. "I already have a wallet" restores a TRON wallet from its 12- or 24-word phrase.

### Do I need an account?

No. There is no sign-up, email, phone number or identity check.

## Recovery phrase

### What is the recovery phrase?

A list of words that holds the keys to your wallet. Anyone who has the words controls the funds, and it is the only backup of the wallet.

### Where should I keep it?

On paper, in order, offline. Do not photograph it, save it in notes or cloud storage, or type it into any website.

### How do I see my phrase again?

Open Settings → Security → Show recovery phrase. The app asks for your PIN, Face ID or Touch ID first.

### What if I lose my phrase?

If you can still open the app, write it down again from Settings → Security. If you lose both the phrase and access to the app, the funds cannot be recovered. We never receive your phrase and cannot restore it.

### Will anyone from {{brand}} ask for my phrase?

Never. Anyone who asks for your recovery phrase or PIN is trying to steal your funds.

## Phone and PIN

### I lost my phone or got a new one. What now?

Install the app on the new device, restore the wallet with your recovery phrase and choose a new PIN. The phrase is not copied through iCloud, so without it the wallet cannot be restored.

### I forgot my PIN. Can you reset it?

No. We cannot reset or look up a PIN. If Face ID or Touch ID is turned on, unlock with it and set a new PIN in Settings → Security → Change PIN. Otherwise the wallet can only be restored from your recovery phrase.

### How does Face ID work in the app?

Turn on Face ID or Touch ID when you create your PIN, or later in Settings → Security. It then unlocks the app and confirms transfers in place of the PIN. The app locks each time it goes to the background.

### What happens if I remove the wallet or delete the app?

Your funds stay on the TRON network either way. To take the wallet off a device, use Settings → Remove wallet before deleting the app. Check that you have your recovery phrase first.

## Sending and receiving

### Which coins and networks are supported?

USDT (TRC-20) and TRX on TRON only. You can send and receive USDT, and receive TRX to pay network fees. Sending TRX from the app is not supported.

### USDT was sent on another network, or as a different coin. Can I get it?

No. USDT sent on another network, such as Ethereum (ERC-20) or BNB Chain (BEP-20), or any other token, is normally lost, and we cannot retrieve it. If an exchange is involved, the exchange may be able to help.

### I sent to the wrong address. Can you reverse it?

No. A transfer is final, and nobody can reverse it, us included. Only the owner of the receiving address can send the funds back. The app checks that an address is a valid TRON address, not that it is the right one.

### Why do I need TRX to send USDT?

Every USDT transfer costs a TRON network fee, currently about {{networkFee}}, paid in TRX from your wallet. The smallest transfer is 1 USDT. TRX can be received at the same address as your USDT. See [Fees](/fees/).

### My transfer shows "Processing". What does that mean?

It has been sent and is waiting for the network to confirm it. The status then changes to "Confirmed".

### The app said my transfer failed. Was anything sent?

The message on the screen tells you. Usually nothing was sent and you can try again. If it says the transfer could not be confirmed, check Activity before sending again, so that you do not pay twice.

### How do I check a transfer on the explorer?

Open the transfer in Activity and choose "View on Tronscan". You can also copy the transaction ID there.

## Prices, alerts and widget

### Where do prices come from?

Prices and charts come from CoinGecko, and the longest chart range from Kraken's public market data, in US dollars. They are indicative only.

### How do price alerts work?

On a coin's screen, set a target price, and the app sends one notification when the price reaches it. Alerts are checked on your device while the app is open and occasionally in the background, so they can arrive late.

### What does the widget show?

Your USDT balance on the Home Screen or Lock Screen. If you hide your balance in the app, the widget hides it too.

## Privacy

### What leaves my device?

Your public wallet address and the transfers you sign go to TronGrid, which connects the app to the TRON network. Price requests go to CoinGecko and Kraken with coin names only. Your recovery phrase, keys and PIN never leave the device. See the [privacy policy](/privacy/).

## Getting help

### How do I contact support?

Write to [{{supportEmail}}](mailto:{{supportEmail}}), our only support channel. Never send your recovery phrase. See [Support](/support/) for what we can and cannot do, and the [security page](/security/) to report a vulnerability.
