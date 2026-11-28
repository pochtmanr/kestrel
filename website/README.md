# Kastrel website

The public site for kastrel.xyz in English, Russian and Simplified Chinese: a landing page, three
guides (about, network fees, help), the legal pages (privacy, terms, risks, restricted territories,
legal notice, support, security), a 404 page and a sitemap.

It is a static [Astro](https://astro.build) site with no cookies, no analytics and no third-party
requests. Keep it that way: the privacy policy says so. The only JavaScript is one small inline script
in `src/layouts/Base.astro` for the menu, the language popup and scroll animation. It loads no
library, stores nothing and sends nothing. With scripts off, the page is static and complete: every
hidden or animated state is scoped to `html.js`, so keep new ones under that class too.

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
| Legal pages and guides | `src/content/legal/<locale>/<page>.md`; the lists are `legalSlugs` and `guideSlugs` in the config |
| Help page | `help.md`: each `###` question and its answer become a folding row |
| Navigation, phone menu, language popup, scroll animation | `src/layouts/Base.astro` (markup and script), `src/styles/global.css` |
| iPhone frame | `src/components/Phone.astro` (SVG drawn over a screenshot) |
| 404 page, sitemap | `src/pages/404.astro`, `src/pages/sitemap.xml.js` |
| Share image and icons | `public/og.png` (1200×630), `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `site.webmanifest` |
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

`public/og.png` shows the home screenshot in the phone frame with the English headline. It is a
picture, not generated at build time: if the home screen or the headline changes, lay it out again
(night background, `backdrop.webp`, logo, headline, `Phone` with the `home` shot) and capture it at
1200×630 with a headless browser.

## Deploy

Any static host works, as long as it serves `404.html` for unknown paths (Vercel does). On Vercel, set the project root to `website/`; the framework is detected
automatically. Point kastrel.xyz at the project. The privacy policy names the host
(`hostingProvider` in the config), so update it if you choose a different one.
