// Builds site/assets/carbon.css and site/assets/icons.js from the pinned Carbon packages.
// Usage (from design/): npm install && npm run build
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as sass from 'sass';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', 'site', 'assets');
mkdirSync(out, { recursive: true });

// 1. Carbon CSS
const css = sass.compile(join(here, 'carbon.scss'), {
  loadPaths: [join(here, 'node_modules')],
  style: 'compressed',
  quietDeps: true,
  silenceDeprecations: ['mixed-decls', 'legacy-js-api', 'import'],
});
writeFileSync(join(out, 'carbon.css'), css.css);
console.log(`carbon.css ${(css.css.length / 1024).toFixed(0)} KB`);

// 2. Carbon icons used by the board (inline SVG strings, 16px viewBox preferred)
const ICONS = [
  'checkmark--filled', 'warning--alt--filled', 'error--filled', 'circle-dash',
  'arrow--up', 'arrow--down', 'arrow--right', 'subtract',
  'chevron--right', 'launch', 'rss', 'information', 'search', 'close',
  'document', 'time', 'notification', 'warning--filled', 'location', 'light', 'asleep', 'arrow--up-right', 'arrow--down-right', 'collapse-all', 'expand-all',
];
const iconDir = join(here, 'node_modules', '@carbon', 'icons', 'svg');
const icons = {};
for (const name of ICONS) {
  let svg;
  for (const size of ['16', '32']) {
    try { svg = readFileSync(join(iconDir, size, `${name}.svg`), 'utf8'); break; } catch { /* try next size */ }
  }
  if (!svg) throw new Error(`icon not found: ${name}`);
  const viewBox = svg.match(/viewBox="([^"]+)"/)[1];
  const inner = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').trim();
  icons[name] = { viewBox, inner };
}
writeFileSync(
  join(out, 'icons.js'),
  '/* Generated from @carbon/icons by design/build.mjs — do not edit. Apache-2.0, IBM Corp. */\n' +
    `window.CARBON_ICONS=${JSON.stringify(icons)};\n`,
);
console.log(`icons.js ${Object.keys(icons).length} icons`);
