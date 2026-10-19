// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

/** Exercise the compiled Nimony client in a real browser against the production WS RPC listener.
 * The Python owning workload supplies its live UI/RPC ports and retains screenshots/diagnostics.
 */
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import path from 'node:path';

const [uiUrl, rpcUrl, folder] = process.argv.slice(2);
assert(uiUrl && rpcUrl && folder, 'Expected UI URL, RPC URL and evidence directory');
const root = process.cwd();
const dependencies = path.join(root, 'build/browser');
const require = createRequire(path.join(dependencies, 'package.json'));
const {chromium} = require('playwright');
const executablePath = (await readFile(path.join(dependencies, 'chrome-path.txt'), 'utf8')).trim();
process.env.PLAYWRIGHT_BROWSERS_PATH = path.join(dependencies, 'browsers');
await mkdir(folder, {recursive: true});
const browser = await chromium.launch({headless: true, ...(executablePath ? {executablePath} : {})});
const page = await browser.newPage({viewport: {width: 1280, height: 1100}});
const errors = [];
const requests = [];
const assets = [];
// Browser decoding must execute precompressed HTML, CSS and Nim-generated JavaScript.
page.on('response', response => assets.push({path: new URL(response.url()).pathname, headers: response.headers()}));
page.on('pageerror', error => errors.push(error.message));
page.on('websocket', socket => {
  socket.on('framesent', ({payload}) => requests.push(JSON.parse(payload.toString())));
});

// Wait for browser callbacks to cross back into Nim after each asynchronous response.
async function responseCount(count) {
  await page.waitForFunction(expected => document.getElementById('responses').textContent === String(expected), count);
  assert.equal(await page.locator('#status').textContent(), 'Connected');
  const envelope = JSON.parse(await page.locator('#response').textContent());
  assert.equal(envelope.jsonrpc, '2.0');
  assert.equal(envelope.result.name, 'Ragnarok');
  assert.equal(envelope.result.implementation, 'Nimony');
  assert.equal(await page.locator('#implementation').textContent(), 'Nimony');
}

try {
  await page.goto(uiUrl);
  await page.locator('#app-state').waitFor({state: 'visible'});
  await page.waitForFunction(() => document.getElementById('app-state').textContent === 'Ready');
  await page.locator('#endpoint').fill(rpcUrl);
  await page.locator('#connect').click();
  await responseCount(1);
  await page.locator('#refresh').click();
  await responseCount(2);
  await page.screenshot({path: path.join(folder, 'desktop.png'), fullPage: true});
  await page.setViewportSize({width: 390, height: 844});
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await page.locator('header').count(), 1);
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await page.screenshot({path: path.join(folder, 'mobile.png'), fullPage: true});
  await page.locator('#disconnect').click();
  assert.equal(await page.locator('#status').textContent(), 'Disconnected');
  assert(await page.locator('#refresh').isDisabled());
  await page.locator('#connect').click();
  await responseCount(3);
  await page.locator('#endpoint').fill('http://127.0.0.1/');
  await page.locator('#connect').click();
  assert.equal(await page.locator('#status').textContent(), 'Invalid WebSocket URL');
  assert(await page.locator('#refresh').isDisabled());
  await page.locator('#endpoint').fill(rpcUrl);
  await page.locator('#connect').click();
  await responseCount(4);
  assert.equal(requests.length, 4);
  assert(requests.every(request => request.method === 'ragnarok_clientInfo' && request.jsonrpc === '2.0' && request.params.length === 0));
  for (const asset of ['/', '/style.css', '/app.js']) {
    const observed = assets.find(response => response.path === asset);
    assert(observed, `Missing browser asset ${asset}`);
    assert.equal(observed.headers['content-encoding'], 'gzip');
    assert.equal(observed.headers.vary, 'Accept-Encoding');
  }
  assert.deepEqual(errors, []);
  await writeFile(path.join(folder, 'results.json'), JSON.stringify({passed: true, browser: await browser.version(), requests, errors, assets}, null, 2));
  console.log('PASS browser DOM, clientInfo, refresh, reconnect, invalid URL and responsive layout');
} catch (error) {
  await page.screenshot({path: path.join(folder, 'failure.png'), fullPage: true});
  throw error;
} finally {
  await browser.close(); // Every failed assertion also retires the browser process and websocket.
}
