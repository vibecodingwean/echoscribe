import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { createIconPng, createLogoSvg, createPromoSvg } from './brand.mjs';
import { makeManifest } from './config.mjs';
import { inlinePopupAssets } from './inline-popup.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const browsers = ['chrome'];
const distRoot = resolve(root, 'dist');

async function bundle(entry, outfile, target, format = 'iife', external = []) {
  await build({
    entryPoints: [resolve(root, entry)],
    outfile,
    bundle: true,
    format,
    platform: 'browser',
    target,
    minify: false,
    sourcemap: false,
    legalComments: 'none',
    external,
    treeShaking: true,
    logLevel: 'warning'
  });
}

async function copyText(source, destination) {
  await mkdir(dirname(destination), { recursive: true });
  await cp(resolve(root, source), destination);
}

await rm(distRoot, { recursive: true, force: true });

for (const browser of browsers) {
  const out = resolve(distRoot, browser);
  const target = 'chrome120';
  await mkdir(resolve(out, 'icons'), { recursive: true });
  await mkdir(resolve(out, 'vendor'), { recursive: true });

  await Promise.all([
    bundle('src/background/main.js', resolve(out, 'background.js'), target),
    bundle('src/popup/main.js', resolve(out, 'popup.js'), target, 'iife', ['/pdf-parser.js']),
    bundle('src/options/main.js', resolve(out, 'options.js'), target),
    bundle('src/pdf/parser.js', resolve(out, 'pdf-parser.js'), target, 'esm')
  ]);

  const popupHtml = await readFile(resolve(root, 'src/popup/popup.html'), 'utf8');
  const popupCss = await readFile(resolve(root, 'src/popup/popup.css'), 'utf8');
  await writeFile(resolve(out, 'popup.html'), inlinePopupAssets(popupHtml, popupCss, new Map()));

  for (const [source, destination] of [
    ['src/options/options.html', 'options.html'],
    ['src/options/options.css', 'options.css'],
    ['src/styles/tokens.css', 'tokens.css'],
    ['node_modules/pdfjs-dist/legacy/build/pdf.worker.min.mjs', 'vendor/pdf.worker.min.mjs'],
    ['LICENSE', 'LICENSE']
  ]) await copyText(source, resolve(out, destination));

  const pdfLicense = await readFile(resolve(root, 'node_modules/pdfjs-dist/LICENSE'), 'utf8');
  await writeFile(resolve(out, 'THIRD_PARTY_NOTICES.txt'), `PDF.js\n${pdfLicense}`);
  await writeFile(resolve(out, 'manifest.json'), `${JSON.stringify(makeManifest(), null, 2)}\n`);
  await writeFile(resolve(out, 'logo.svg'), createLogoSvg());
  for (const size of [16, 32, 48, 96, 128]) {
    await writeFile(resolve(out, `icons/icon-${size}.png`), createIconPng(size));
  }
}

await mkdir(resolve(root, 'assets'), { recursive: true });
await writeFile(resolve(root, 'assets/logo.svg'), createLogoSvg());
await writeFile(resolve(root, 'assets/store-promo.svg'), createPromoSvg());

console.log(`Built ${browsers.length} browser targets in ${distRoot}`);
