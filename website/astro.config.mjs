import { defineConfig } from 'astro/config';
import { site, placeholders } from './src/site.config.mjs';

const missing = placeholders();
if (missing.length) {
  console.warn(
    `\n[kastrel] Not ready to go live. Fill in these values in src/site.config.mjs: ${missing.join(', ')}\n`,
  );
}

export default defineConfig({
  site: site.url,
  trailingSlash: 'always',
  build: { format: 'directory' },
});
