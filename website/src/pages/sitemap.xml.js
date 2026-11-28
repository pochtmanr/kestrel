// The sitemap, written by hand so the site needs no integration: every page in every
// language, each with links to its translations.
import { site, locales, pageSlugs, href } from '../lib.mjs';

export function GET() {
  const abs = (locale, slug) => new URL(href(locale, slug), site.url).href;
  const urls = ['', ...pageSlugs].flatMap((slug) =>
    locales.map((l) => {
      const alternates = locales
        .map((a) => `    <xhtml:link rel="alternate" hreflang="${a.lang}" href="${abs(a.code, slug)}"/>`)
        .join('\n');
      return `  <url>\n    <loc>${abs(l.code, slug)}</loc>\n${alternates}\n    <xhtml:link rel="alternate" hreflang="x-default" href="${abs('en', slug)}"/>\n  </url>`;
    }),
  );
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls.join('\n')}\n</urlset>\n`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
}
