# Kastrel website

The public site for kastrel.xyz: a landing page plus the legal pages (privacy, terms, risks, restricted
territories, legal notice, support, security) in English, Russian and Simplified Chinese.

It is a static [Astro](https://astro.build) site with no client-side JavaScript, no cookies, no
analytics and no third-party requests. Keep it that way: the privacy policy says so.

## Run it

```bash
cd website
npm install
npm run dev        # http://localhost:4321
npm run build      # output in dist/
npm run preview    # serve the built site
```

## Before going live

`src/site.config.mjs` holds every fact that appears across the site. The build prints a warning while
any of these are still placeholders:

- `companyNumber`, `registeredOffice` (and confirm `registeredIn`)
- `downloadUrl` (TestFlight or App Store link; while empty the site shows "Coming soon")

Also create the mailboxes `support@`, `privacy@` and `security@kastrel.xyz`, and go through the lawyer
checklist in `docs/legal-research.md`.

## Where things are

| To change | Edit |
|---|---|
| Company details, emails, download link, dates | `src/site.config.mjs` |
| Landing page text | `src/i18n/en.mjs`, `ru.mjs`, `zh.mjs` |
| Legal pages | `src/content/legal/<locale>/<page>.md` |
| Colours, type, layout | `src/styles/global.css` (tokens mirror `Kestrel/Shared/Theme.swift`) |
| Header, footer, company disclosures | `src/layouts/Base.astro` |
| Screenshots | `public/shots/` (WebP, 660 px wide) |

Legal pages and strings can use `{{tokens}}` from the config, for example `{{company}}` or
`{{supportEmail}}`.

## Rules for the text

- **Three languages, always.** A change to a legal page or a string goes into all three locales.
  English is the controlling version. Translate by hand.
- **Functional copy only.** No "buy", "earn", "invest", price or return claims, and no rewards or
  referral offers. This is a UK financial promotions precaution: see `docs/legal-research.md`.
- **The privacy policy must match the app.** If the app starts contacting a new service, or push
  notifications or the support chat are switched on, update `privacy.md` in all locales first.
- **The restricted-territories list** lives in `restricted.md` in each locale.
- When legal text changes in substance, bump `lastUpdated` in the config.

## Refreshing screenshots

Capture with `scripts/capture-screenshots.sh` from the repo root, then convert:

```bash
S=fastlane/screenshot-studio/assets/shots/en-US/iphone
for n in home send receive activity security; do
  cwebp -q 82 -resize 660 0 $S/$n.png -o website/public/shots/$n.webp
done
```

## Deploy

Any static host works. On Vercel, set the project root to `website/`; the framework is detected
automatically. Point kastrel.xyz at the project. The privacy policy names the host
(`hostingProvider` in the config), so update it if you choose a different one.
