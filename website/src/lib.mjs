import { marked } from 'marked';
import { site, locales, legalSlugs, guideSlugs, pageSlugs } from './site.config.mjs';
import en from './i18n/en.mjs';
import ru from './i18n/ru.mjs';
import zh from './i18n/zh.mjs';

const tokens = { ...site, lastUpdated: undefined };

/** Replaces {{key}} tokens with values from site.config.mjs, through nested objects and arrays. */
export function fill(value, locale = 'en') {
  if (typeof value === 'string') {
    return value.replace(/\{\{(\w+)\}\}/g, (whole, key) => {
      if (key === 'lastUpdated') return site.lastUpdated[locale];
      return tokens[key] ?? whole;
    });
  }
  if (Array.isArray(value)) return value.map((v) => fill(v, locale));
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, fill(v, locale)]));
  }
  return value;
}

const strings = { en, ru, zh };
export const t = (locale) => fill(strings[locale], locale);

export const localeOf = (param) => locales.find((l) => l.path === (param ?? '')) ?? locales[0];

/** Site-relative link to a page in a locale. An empty slug is the landing page. */
export function href(locale, slug = '') {
  const { path } = locales.find((l) => l.code === locale);
  return '/' + [path, slug].filter(Boolean).map((p) => p + '/').join('');
}

// Legal pages are Markdown with a two-line front matter (title, description).
// They are read raw so that {{tokens}} are filled in before the Markdown is parsed,
// which lets email addresses and URLs from the config become links.
const files = import.meta.glob('./content/legal/*/*.md', { query: '?raw', import: 'default', eager: true });

export function legalPage(locale, slug) {
  const raw = files[`./content/legal/${locale}/${slug}.md`];
  if (!raw) throw new Error(`Missing legal page: ${locale}/${slug}.md`);
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`Missing front matter: ${locale}/${slug}.md`);
  const meta = Object.fromEntries(
    match[1].split('\n').map((line) => {
      const i = line.indexOf(':');
      return [line.slice(0, i).trim(), fill(line.slice(i + 1).trim(), locale)];
    }),
  );
  return { ...meta, html: marked.parse(fill(match[2], locale), { gfm: true }) };
}

export { site, locales, legalSlugs, guideSlugs, pageSlugs };
