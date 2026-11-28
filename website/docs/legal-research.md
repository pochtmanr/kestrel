# Legal research: Kastrel Wallet

Research date: 27 November 2026. This is research to brief a lawyer, **not legal advice**. The pages on
the site are careful drafts built on it. Have a qualified UK solicitor review them before launch.

Facts assumed: Simnetiq Ltd is a UK private limited company. The app is a non-custodial iOS wallet for
USDT (TRC-20) and TRX on TRON. Keys are created and kept on the device. Send and receive only: no swap,
no exchange, no fiat, no card, no account, no KYC. No fee or commission during launch. Offered
worldwide apart from restricted territories, in English, Russian and Simplified Chinese.

Labels: **Settled** (clear in law or official text), **Uncertain** (no authoritative answer),
**Depends** (on where users or marketing are).

## 1. Is the product regulated?

| Regime | Position | Status |
|---|---|---|
| EU MiCA (Reg. 2023/1114) | Recital 83: "Hardware or software providers of non-custodial wallets should not fall within the scope of this Regulation." Custody means holding the assets or the means of access, which the app does not | Settled |
| EU Transfer of Funds Regulation (2023/1113) | Duties for transfers to self-hosted addresses sit on exchanges, not on wallet software. Users may be asked by an exchange to prove they control their address | Settled |
| UK Money Laundering Regulations 2017, reg. 14A | A "custodian wallet provider" safeguards cryptoassets or keys on behalf of customers; an "exchange provider" exchanges. The app does neither, so no FCA registration | Settled |
| UK FSMA cryptoasset regime (SI 2026/102, in force 25 Oct 2027) | Safeguarding turns on control of the means of access. No control, no safeguarding. No express carve-out for wallet software | Settled on dates, uncertain at the edges |
| US FinCEN guidance FIN-2019-G001 | Providers of unhosted wallet software are not money transmitters | Settled as guidance |
| US state money transmitter laws | Mostly do not reach software without control, but not uniform | Depends |
| FATF (Oct 2021) | Pure software providers of unhosted wallets are not VASPs | Settled as a standard |

### What would change this

| Future feature | Effect |
|---|---|
| A fee or subscription on its own | Low. Still no custody or exchange. Regulators look at substance, so review it first |
| Swaps or an on-ramp we operate or route | Regulated exchange activity. Use a licensed partner under its own terms |
| Sponsored transactions (we pay TRX, take USDT back) | Economically an exchange with us as counterparty. High risk |
| Card | Needs a licensed e-money or payments partner |
| Key recovery or cloud backup run by us | May become custody |
| Push notifications linking an address to a device | Not a licensing issue, but a privacy one: see section 4 |

## 2. The highest risk: UK financial promotions

- Since 8 October 2023, FSMA s.21 forbids communicating, in the course of business, an invitation or
  inducement to engage in investment activity relating to qualifying cryptoassets, unless the promotion
  is made or approved by an authorised firm, made by an MLR-registered cryptoasset business, or exempt.
  USDT is a qualifying cryptoasset. Breach is a criminal offence. It applies to promotions capable of
  having an effect in the UK, wherever they are made.
- The FCA's own guidance gives "an unregistered firm (eg a non-custodial wallet provider)" as its
  example of a firm making illegal promotions. A non-custodial provider cannot use the registered-firm
  route, because it has nothing to register for.
- **Uncertain:** whether marketing a pure send/receive tool is an "inducement to engage in investment
  activity" at all. No authority settles it. The cases the FCA has acted on involved buy, swap or
  on-ramp features.

How the site handles it:

- Copy is functional only: hold, send, receive. No "buy", "earn", "grow", "invest", no price or return
  claims, no incentives or referral rewards.
- A risk warning in the footer of every page, a risk disclosure page, and a clear statement that the
  company is not authorised or regulated by the FCA.

Still to do: get a solicitor's view before any UK-facing marketing. Apply the same rules to the App
Store listing and to social posts. Note that Google Ads allows UK crypto wallet ads only from
FCA-registered advertisers.

## 3. Sanctions and restricted territories

- Market practice among self-custody wallets is a restricted-territories clause covering Cuba, Iran,
  North Korea, Syria and the Crimea, Donetsk and Luhansk regions, plus sanctioned persons and a ban on
  VPN circumvention. Some also exclude Russia.
- **Russia is an open decision.** EU Reg. 833/2014 Art. 5b bans providing "crypto-asset services"
  (defined by reference to MiCA) to Russian nationals, residents and entities. Because MiCA excludes
  non-custodial wallet software, a pure software provider is arguably outside it, but this is
  uncertain, and UK Russia sanctions need the same check. Russia also bans crypto advertising
  (since 17 Aug 2024). Russian-language pages are not the same as targeting Russia, but get sanctions
  advice before promoting to users resident there.
- **Mainland China:** virtual-currency business is treated as illegal financial activity. The site
  lists mainland China as restricted and the Chinese pages say so. Exclude the China mainland
  storefront in App Store Connect.
- The app has no geo-blocking or sanctions screening. The restriction is contractual plus the choice of
  App Store storefronts. A lawyer should confirm that is enough for a pure software provider.
- Tether can freeze, blacklist and destroy USDT at any address and does so regularly on TRON. This is
  disclosed in the terms and the risk page.

## 4. Privacy

- UK GDPR applies. The company is the controller for the little it holds: support emails, website
  server logs, and aggregated App Store statistics.
- EDPB Guidelines 02/2025 (v2.0, July 2026): a wallet address is personal data when it can be linked to
  an identifiable person. IP addresses in server logs should be treated as personal data.
- The app sends the wallet address and IP to TronGrid, and IP only to CoinGecko and Kraken, directly
  from the device. The company never receives these. The policy names each service and says so.
- No cookies, analytics or third-party requests on the site, so no consent banner is needed under PECR.
- **EU representative (GDPR Art. 27):** a UK company that offers a service to people in the EU must
  appoint one unless processing is occasional. With no accounts and almost no data this is arguable,
  but ask the lawyer. The policy does not name one.
- **ICO data protection fee:** most UK organisations that process personal data must register and pay
  the annual fee. Check and register.
- When push notifications or the support chat are switched on, the policy, the App Privacy label and
  the privacy manifest must all be updated first. The policy already says this.

Apple App Privacy label today: "Data Not Collected" is consistent with the code, because nothing
reaches a server the company controls. Re-check when any backend feature goes live.

## 5. Company disclosures (UK)

- Company (Trading Disclosures) Regulations 2015, regs 24 and 25: registered name, part of the UK where
  registered, company number and registered office address on the website. These are in the footer of
  every page and on the legal notice page.
- Electronic Commerce (EC Directive) Regulations 2002, reg. 6: name, geographic address, email, and
  register details, easily and permanently accessible. Covered by the same pages. Add a VAT number if
  the company registers for VAT.

## 6. Terms of use: choices made

- Modelled on the clauses that established self-custody wallets consistently use (non-custodial nature,
  recovery phrase, irreversibility, network fees, third parties, issuer risk, eligibility, prohibited
  use, restricted territories, "as is", liability, changes, trademarks).
- Consumer Rights Act 2015: unfair-terms rules apply even to a free app. So the terms do not use a
  blanket exclusion. They keep liability for death or injury from negligence, for fraud, and anything
  that cannot be excluded, and they preserve statutory rights.
- **Liability cap of £100:** common in the market, but a court could find it unfair against a consumer.
  Ask the lawyer whether to keep it.
- No arbitration clause. For consumer claims under £5,000 one would be automatically unfair
  (Arbitration Act 1996 s.91). English law and courts, with consumers keeping home-country protections.
- Future fees: the terms promise notice in the app and on the site before any fee applies.
- An Apple clause (third-party beneficiary) is included, as Apple's guidelines expect for a custom EULA.

## 7. Apple App Store

- Guideline 3.1.5(i): wallet apps must come from a developer enrolled as an organisation.
- App Review often asks transfer-only wallets for licensing evidence. Prepare a review note: keys are
  generated and stored only on the device; no exchange, purchase or fiat features; no fee; the company
  never transmits value for users.
- Required: a privacy policy URL (in the listing and in the app) and a support URL. Both now exist.
- EU Digital Services Act: trader details (address, phone, email) are shown on EU product pages.
- Set the age rating to match the terms (18+).

## 8. Sign-off checklist for a lawyer

1. UK financial promotions position for the site, the App Store listing and social posts.
2. Sanctions: Russia (EU Art. 5b, UK regulations), and whether contractual restrictions are enough.
3. Terms of use: enforceability against consumers, the £100 cap, the future-fee clause.
4. Privacy policy, the Art. 27 representative question, and ICO registration.
5. Trademark clearance for "Kastrel" in the UK, EU and US (the roadmap notes "Kestrl" and a Solana
   project called "Kestrel"). Use of the Tether and TRON names and marks.
6. A fresh review before any fee, swap, sponsored transaction, card or push feature.

## Sources

- MiCA recital 83: https://www.springlex.eu/en/packages/mica/mica-regulation/article-75/ (mirror; confirm on EUR-Lex)
- UK MLRs reg. 14A: https://legislation.gov.uk/uksi/2017/692/regulation/14A
- UK cryptoasset regulations 2026: https://www.legislation.gov.uk/uksi/2026/102/data.htm
- FCA, cryptoasset financial promotions: https://www.fca.org.uk/firms/cryptoasset-financial-promotions-and-fiat-crypto-ramp-services
- FCA PS23/6: https://www.fca.org.uk/publications/policy-statements/ps23-6-financial-promotion-rules-cryptoassets
- Skadden on FCA enforcement: https://www.skadden.com/insights/publications/2024/08/fca-reports-spotty-compliance-with-crypto
- FinCEN 2019 guidance (summary): https://coincenter.org/fincens-new-cryptocurrency-guidance-matches-coin-center-recommendations/
- EU self-hosted wallet rules (summary): https://notabene.id/post/a-deep-dive-into-self-hosted-wallet-transaction-requirements-under-the-eu-tfr
- EU 19th sanctions package (summary): https://www.matheson.com/insights/the-european-unions-19th-sanctions-package-against-russia-key-takeaways/
- Tether terms: https://tether.to/en/legal/
- EDPB blockchain guidelines: https://www.edpb.europa.eu/system/files/2026-07/edpb_guidelines_202502_blockchain_v2_en.pdf
- ICO on cookies: https://ico.org.uk/for-organisations/guide-to-pecr/cookies-and-similar-technologies/
- Trading disclosures: https://www.legislation.gov.uk/uksi/2015/17/regulation/24
- E-commerce regulations reg. 6: https://www.legislation.gov.uk/uksi/2002/2013/regulation/6
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Wallet terms compared: https://trustwallet.com/terms-of-service, https://metamask.com/terms-of-use, https://www.kraken.com/wallet/legal
