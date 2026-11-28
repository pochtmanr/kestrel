// The one place for facts that appear across the site and the legal pages.
// Legal pages and UI strings reference these as {{key}} tokens.
//
// Anything that still starts with "[TO ADD" is a placeholder: the build prints a warning
// for each one, and the site must not go live until they are all filled in.

export const site = {
  url: 'https://kastrel.xyz',
  brand: 'Kastrel',
  appName: 'Kastrel Wallet',

  // Company (UK trading disclosures: these appear in the footer of every page).
  company: 'Simnetiq Ltd',
  registeredIn: 'England and Wales', // confirm against the certificate of incorporation
  companyNumber: '[TO ADD: company number]',
  registeredOffice: '[TO ADD: registered office address]',

  // Contact. Create these mailboxes before launch.
  supportEmail: 'support@kastrel.xyz',
  privacyEmail: 'privacy@kastrel.xyz',
  securityEmail: 'security@kastrel.xyz',

  // TestFlight or App Store link. While empty, the site shows "Coming soon" instead of a button.
  downloadUrl: '',

  // Shown in the privacy policy as the processor that serves this website.
  hostingProvider: 'Vercel Inc.',

  // Legal pages: bump when the text changes in substance.
  lastUpdated: { en: '27 November 2026', ru: '27 ноября 2026 г.', zh: '2026年11月27日' },

  // Facts quoted in copy. Keep in step with the app (SendRules.swift, ReviewTransferSheet.swift).
  networkFee: '7–14 TRX',
  minAge: '18',
};

export const locales = [
  { code: 'en', path: '', lang: 'en', label: 'English' },
  { code: 'ru', path: 'ru', lang: 'ru', label: 'Русский' },
  { code: 'zh', path: 'zh', lang: 'zh-Hans', label: '简体中文' },
];

export const legalSlugs = ['privacy', 'terms', 'risks', 'restricted', 'legal', 'support', 'security'];

export function placeholders() {
  const missing = Object.entries(site)
    .filter(([, v]) => typeof v === 'string' && v.startsWith('[TO ADD'))
    .map(([k]) => k);
  if (!site.downloadUrl) missing.push('downloadUrl');
  return missing;
}
