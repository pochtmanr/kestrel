---
title: Privacy policy
description: What {{appName}} and this website do with your data. The short answer is very little: no account, no analytics, and your keys never leave your device.
---

This policy explains what data is involved when you use the {{appName}} app for iOS (the "app") and the website at kastrel.xyz (the "site"), and what we do with it.

> **In short**
>
> - We never receive your recovery phrase, private keys or PIN. They stay on your device.
> - The app has no account, no sign-up and no analytics, advertising or tracking code.
> - To show balances and send transfers, the app sends your public wallet address to a TRON network provider. That provider, not us, receives the request.
> - This site sets no cookies and loads nothing from third parties.

## 1. Who we are

{{appName}} is published by **{{company}}**, a company registered in {{registeredIn}} with company number {{companyNumber}}. Our registered office is {{registeredOffice}}.

{{company}} is the controller of the personal data described in this policy, where we hold any. You can reach us about privacy at [{{privacyEmail}}](mailto:{{privacyEmail}}).

## 2. What we never collect

- Your recovery phrase, private keys or PIN
- Face ID or Touch ID data (this is handled by iOS and never given to the app)
- Your name, email address, phone number or identity documents
- Your contacts, photos or location
- Advertising identifiers, or any record of how you use the app

The app has no user accounts. We do not run a server that receives your wallet address, balance or transaction history.

## 3. Data kept on your device

The app stores the following on your device only. We cannot see or retrieve any of it.

| Data | Where it is kept |
|---|---|
| Recovery phrase | iOS Keychain, on this device only, with no iCloud sync |
| PIN | iOS Keychain, as a salted hash |
| Face ID setting | iOS Keychain |
| Wallet address, balances and recent transfers | App storage shared with the app's widget |
| Transaction history cache | A file in the app's storage |
| Notes on transfers, address names, price alerts | App settings |
| Language, appearance and text size | App settings |

**Camera.** The app uses the camera only to scan a wallet address from a QR code. Images are processed on the device and are not saved or sent anywhere.

**Notifications.** If you set a price alert, the app asks for permission to show notifications. Alerts are checked and delivered on your device. We do not operate a notification server, and no push token is sent to us.

## 4. Data that leaves your device

The app connects directly from your device to the services below. These requests do not pass through our servers, and we do not receive them. Each provider acts as an independent controller of what it receives, under its own privacy policy.

| Service | What it receives | Why |
|---|---|---|
| **TronGrid** (TRON network API) | Your public wallet address, the transfers you sign and broadcast, and your IP address | To read your balance and history, estimate network fees, and send your transfers to the TRON network |
| **CoinGecko** | The names of the coins (USDT, TRX) and your IP address. Never your wallet address | To show prices and charts |
| **Kraken** (public market data) | The names of the coins and your IP address. Never your wallet address | To show long-range price charts |
| **Tronscan** | The transaction you choose to view, and your IP address | Only when you tap a link to see a transaction in your browser |
| **Apple** | Whatever Apple collects when you download and use apps from the App Store | Distribution of the app. If you have agreed to share analytics with developers in iOS settings, Apple gives us aggregated, anonymous usage and crash statistics |

Requests to TronGrid include an app-wide key that is the same for every user. It does not identify you. The app's widget makes the same balance requests to TronGrid in the background so that it can stay up to date.

Because TronGrid sees both your IP address and your wallet address, it is technically able to associate them. If this matters to you, be aware of it before using the app.

## 5. The blockchain is public

Transfers on the TRON network are public and permanent. Anyone can see the addresses, amounts and times of transactions. Nobody, including us, can change or delete them. If someone can connect your address to you, they can see its whole history.

## 6. This website

The site is static. It sets **no cookies**, uses no analytics, and loads no fonts, scripts or images from third parties. For this reason it does not show a cookie banner.

Our hosting provider, {{hostingProvider}}, processes standard server logs on our behalf when you load a page: your IP address, browser type, the page requested and the time. We use these only to deliver the site and keep it secure.

## 7. When you contact us

If you email us, we receive your email address and whatever you write. We use it to answer you and to keep a record of the request. Please never send us your recovery phrase or private keys. We will never ask for them.

## 8. Why we are allowed to process data

Under the UK GDPR and the EU GDPR we rely on these legal bases:

| Activity | Legal basis |
|---|---|
| Answering support and privacy requests | Legitimate interests (responding to people who contact us), or steps taken at your request |
| Website server logs for delivery and security | Legitimate interests (running a secure website) |
| Aggregated App Store statistics from Apple | Legitimate interests (understanding whether the app works) |
| Keeping records where the law requires it, and responding to lawful requests from authorities | Legal obligation |

We do not make decisions about you by automated means, and we do not build profiles.

## 9. Who we share data with

We do not sell personal data and we do not share it for advertising. The limited data we hold may be handled by:

- our hosting provider ({{hostingProvider}}) and our email provider, acting on our instructions;
- professional advisers such as lawyers and accountants, where needed;
- courts, regulators or law enforcement, where the law requires us to disclose it.

Because the wallet is self-custody, we hold no keys, balances or transaction records. In response to any request about a wallet we can provide only what we actually hold, which is normally nothing beyond correspondence with us.

## 10. International transfers

Our providers may process data outside the United Kingdom and the European Economic Area, including in the United States. Where they do, we rely on a UK or EU adequacy decision or on approved standard contractual clauses.

The services in section 4 are contacted directly by your device and may be located anywhere in the world.

## 11. How long we keep data

| Data | Kept for |
|---|---|
| Emails and support requests | Up to 24 months after the last message, unless we need them longer to deal with a dispute or a legal duty |
| Website server logs | A short period set by our hosting provider, normally no more than 30 days |
| Data on your device | Until you erase the wallet or delete the app (see section 13) |

## 12. Your rights

Depending on where you live, you have the right to ask for access to your personal data, to have it corrected or erased, to restrict or object to our use of it, and to receive a copy in a portable format. To use any of these rights, email [{{privacyEmail}}](mailto:{{privacyEmail}}). We reply within one month.

Because we hold no account for you, we usually cannot link a wallet address to a person. We may ask for information to confirm that a request really comes from you.

You can complain to the UK Information Commissioner's Office at [ico.org.uk](https://ico.org.uk/make-a-complaint/). If you live in the EU, you can also complain to your local data protection authority. We would appreciate the chance to put things right first.

## 13. Deleting your data

- **On your device.** In the app, go to Settings and choose to erase the wallet. This removes the recovery phrase, PIN, wallet data and history from the device. Do this before deleting the app, because iOS can keep Keychain items after an app is removed. Erasing the wallet does not affect your funds, which remain on the TRON network and can be restored with your recovery phrase.
- **Held by us.** Email [{{privacyEmail}}](mailto:{{privacyEmail}}) to ask us to delete your correspondence.
- **On the blockchain.** Transactions cannot be deleted by anyone.

## 14. Children

The app and the site are for adults aged {{minAge}} or over. We do not knowingly collect data from children.

## 15. Security

Secrets are stored in the iOS Keychain, restricted to the device and available only while it is unlocked. The app locks behind a PIN, with optional Face ID, and hides its content in the app switcher. Transfers are signed on the device, and only the signed transaction is sent to the network. No system is perfectly secure, and you are responsible for protecting your device and your recovery phrase.

## 16. Features that are not active yet

The app contains groundwork for two features that are **not currently switched on**: push notifications for incoming transfers, and an in-app support chat. Neither sends any data today. If we introduce either one, it would involve new data (for example, linking a wallet address to a notification token), and we will update this policy before it starts.

## 17. Changes to this policy

We will post any changes on this page and update the date at the top. If a change is significant, we will also announce it in the app or on the site before it takes effect.

## 18. Contact

{{company}}, {{registeredOffice}}
[{{privacyEmail}}](mailto:{{privacyEmail}})
