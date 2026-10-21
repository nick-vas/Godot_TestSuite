// Opens a Godot web export in a real browser and judges it, as `export -Run` does for desktop builds.
//   node web-smoke.mjs <export folder> --browser=chromium|chrome|msedge|firefox|webkit [--timeout=60000]
//        [--seconds=3] [--screenshot=<png>] [--coi]
// It serves the folder itself on 127.0.0.1, with the Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy headers
// only when --coi is given (a threads build needs them; itch.io and GitHub Pages send none). Passes when the engine
// started (Godot's #status overlay is removed) and, after --seconds of play, no page error, failed request, console error
// or Godot ERROR / SCRIPT ERROR line appeared. Prints one line "@@web <json>". Needs the playwright package (NODE_PATH).
import { createRequire } from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const require = createRequire(import.meta.url);
const args = Object.fromEntries(process.argv.slice(3).map(a => a.replace(/^--/, '').split(/=(.*)/s).slice(0, 2)).map(([k, v]) => [k, v ?? true]));
const dir = path.resolve(process.argv[2] || '.');
const browserName = args.browser || 'chromium';
const timeoutMs = +(args.timeout || 60000);
const result = { browser: browserName, ok: false, started: false, startMs: null, notice: '', crossOriginIsolated: null,
  renderer: null, screenshot: args.screenshot || null, errors: [], console: [] };
const finish = (code) => { console.log('@@web ' + JSON.stringify(result)); process.exit(code); };

let playwright;
try { playwright = require('playwright'); } catch { result.errors.push('[setup] the playwright package was not found'); finish(2); }

const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png',
  '.json': 'application/json', '.pck': 'application/octet-stream', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  const f = path.join(dir, path.normalize(p));
  if (!f.startsWith(dir) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
  const headers = { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' };
  if (args.coi) { headers['Cross-Origin-Opener-Policy'] = 'same-origin'; headers['Cross-Origin-Embedder-Policy'] = 'require-corp'; }
  res.writeHead(200, headers);
  fs.createReadStream(f).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/`;

// Headless Chromium draws WebGL 2 with SwiftShader when there is no GPU; Chrome 137+ wants this flag to keep doing so.
// Headless Firefox on a machine without a GPU (a GitHub runner) blocks WebGL 2 ("features required ... are missing:
// WebGL2") unless it is forced on, which lets it render in software.
const engine = { chromium: 'chromium', chrome: 'chromium', msedge: 'chromium', firefox: 'firefox', webkit: 'webkit' }[browserName];
if (!engine) { result.errors.push(`[setup] unknown browser ${browserName}`); server.close(); finish(2); }
let browser;
try {
  browser = await playwright[engine].launch({ headless: true, channel: ['chrome', 'msedge'].includes(browserName) ? browserName : undefined,
    args: engine === 'chromium' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : [],
    firefoxUserPrefs: engine === 'firefox' ? { 'webgl.force-enabled': true, 'webgl.disabled': false } : undefined });
} catch (e) {
  result.errors.push(`[setup] ${browserName} could not start: ${String(e.message).split('\n')[0]}`);
  server.close();
  finish(2);
}
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on('console', m => {
  const text = m.text();
  result.console.length < 60 && result.console.push(`[${m.type()}] ${text}`);
  if (m.type() === 'error' || /^\s*(USER |SCRIPT |SHADER )?ERROR:/.test(text)) result.errors.push(`[console] ${text}`);
});
page.on('pageerror', e => result.errors.push(`[pageerror] ${e.message}`));
page.on('requestfailed', r => result.errors.push(`[requestfailed] ${r.url()} ${r.failure()?.errorText ?? ''}`));
const t0 = Date.now();
try {
  await page.goto(url, { waitUntil: 'load', timeout: timeoutMs });
  // Godot's page removes #status when the engine has started, or shows #status-notice when it cannot start.
  await page.waitForFunction(() => {
    const notice = document.getElementById('status-notice');
    return !document.getElementById('status') || (notice && getComputedStyle(notice).display !== 'none' && notice.innerText.trim() !== '');
  }, null, { timeout: timeoutMs });
  result.started = await page.evaluate(() => !document.getElementById('status'));
  result.notice = await page.evaluate(() => document.getElementById('status-notice')?.innerText?.trim() || '');
  result.startMs = Date.now() - t0;
  if (!result.started) result.errors.push(`[not started] ${result.notice}`);
  else await page.waitForTimeout(1000 * +(args.seconds || 3));
  Object.assign(result, await page.evaluate(() => {
    const gl = document.createElement('canvas').getContext('webgl2');
    const info = gl && gl.getExtension('WEBGL_debug_renderer_info');
    return { crossOriginIsolated: self.crossOriginIsolated, renderer: gl ? (info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : 'WebGL 2') : null };
  }));
  if (args.screenshot) await page.screenshot({ path: args.screenshot });
} catch (e) {
  result.errors.push(`[timeout] ${String(e.message).split('\n')[0]}`);
}
result.ok = result.started && result.errors.length === 0;
await browser.close();
server.close();
finish(result.ok ? 0 : 1);
