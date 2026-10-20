// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

/** Exercise the actual Nim RPC client with a deterministic browser WebSocket peer.
 * No transport internals are exposed: the compiled fixture uses only its public RPC API.
 */
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';

export async function checkRpcClient(browser, root, folder) {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    // Browser-owned fake sockets let tests reorder replies and updates without timing a real node.
    await page.addInitScript(() => {
      const schedule = globalThis.setTimeout.bind(globalThis);
      const cancel = globalThis.clearTimeout.bind(globalThis);
      globalThis.rpcTimers = new Set();
      globalThis.rpcMaxTimers = 0;
      globalThis.setTimeout = (callback, delay, ...args) => {
        const identity = schedule(() => { globalThis.rpcTimers.delete(identity); callback(...args); }, delay);
        if (delay === 25) {
          globalThis.rpcTimers.add(identity);
          globalThis.rpcMaxTimers = Math.max(globalThis.rpcMaxTimers, globalThis.rpcTimers.size);
        }
        return identity;
      };
      globalThis.clearTimeout = identity => { globalThis.rpcTimers.delete(identity); cancel(identity); };
      globalThis.rpcEvents = [];
      globalThis.rpcAccepted = [];
      globalThis.rpcSockets = [];
      globalThis.WebSocket = class {
        static OPEN = 1;
        constructor(url) {
          this.url = url;
          this.readyState = 0;
          this.sent = [];
          globalThis.rpcSockets.push(this);
          setTimeout(() => { this.readyState = 1; this.onopen?.(); }, 0);
        }
        send(text) { this.sent.push(JSON.parse(text)); }
        close() { this.readyState = 3; }
        receive(value) { this.onmessage?.({data: typeof value === 'string' ? value : JSON.stringify(value)}); }
      };
    });
    await page.goto('about:blank');
    await page.addScriptTag({content: await readFile(path.join(root, 'build/tests/ui-rpc/rpc-test.js'), 'utf8')});
    await page.waitForFunction(() => globalThis.rpcSockets[0]?.sent.length === 4);
    const events = () => page.evaluate(() => globalThis.rpcEvents);
    const sent = () => page.evaluate(() => globalThis.rpcSockets.at(-1).sent);
    const action = name => page.evaluate(name => globalThis[name](), name);
    const receive = value => page.evaluate(value => globalThis.rpcSockets.at(-1).receive(value), value);
    const reply = (id, result) => receive({jsonrpc: '2.0', id, result});
    const update = (subscription, value, method = 'subscribeBestBlock') => receive({
      jsonrpc: '2.0', method, params: {subscription, result: value},
    });
    const opened = async () => {
      await action('rpcTestReconnect');
      await page.waitForFunction(() => globalThis.rpcSockets.at(-1).readyState === 1);
    };
    const initial = await sent();
    assert.deepEqual(initial.map(value => value.method), [
      'subscribeBestBlock', 'subscribeBestBlock', 'ragnarok_clientInfo', 'ragnarok_clientInfo',
    ]);
    assert.equal(new Set(initial.map(value => value.id)).size, 4);
    // Notification selectors and request IDs are distinct namespaces, even when their numbers match.
    const selector = initial[2].id;
    await reply(initial[3].id, {name: 'second'});
    await reply(initial[1].id, 4294967295);
    await update(4294967295, {slot: 20});
    await reply(initial[0].id, selector);
    await update(selector, {slot: 10});
    assert(!(await events()).some(value => value.label === 'first'));
    await reply(initial[2].id, {name: 'first'});
    assert.deepEqual((await events()).map(value => value.label), [
      'second', 'ack2', 'update2', 'ack1', 'update1', 'first',
    ]);
    assert.equal((await events()).find(value => value.label === 'update2').id, 4294967295);
    const beforeUnknown = (await events()).length;
    await receive('{');
    await reply(2147483647, 'unknown');
    await reply(initial[2].id, 'duplicate');
    await update(selector, 'wrong method', 'subscribeStatistics');
    await update(999, 'unknown selector');
    assert.equal((await events()).length, beforeUnknown);

    // One timed-out call leaves another outstanding call and both active streams usable.
    await action('rpcTestDeadlines');
    const deadlines = (await sent()).slice(-2);
    await page.waitForFunction(() => globalThis.rpcEvents.some(value => value.label === 'timeout'));
    assert.equal((await events()).filter(value => value.label === 'timeout')[0].status, 'TimedOut');
    assert.equal((await events()).filter(value => value.label === 'timeout')[0].id, deadlines[0].id);
    assert(!(await events()).some(value => value.label === 'held'));
    await update(selector, {slot: 11});
    await update(4294967295, {slot: 21});
    await reply(deadlines[1].id, {held: true});
    await reply(deadlines[0].id, 'late');
    assert.equal((await events()).filter(value => value.label === 'timeout').length, 1);

    // Deadline callbacks may enqueue another call without multiplying scheduler timers.
    await action('rpcTestReentrant');
    await page.waitForFunction(() => globalThis.rpcEvents.some(value => value.label === 'reentrant'));
    const retried = (await sent()).at(-1);
    assert.equal(retried.method, 'after-timeout');
    await reply(retried.id, 'retried');
    assert.equal(await page.evaluate(() => globalThis.rpcMaxTimers), 1);

    // Unsubscribe errors preserve routing; only its successful boolean ACK ends the selected stream.
    await action('rpcTestExtra');
    const extra = (await sent()).at(-1);
    await action('rpcTestUnsubscribe');
    const rejected = (await sent()).at(-1);
    const pendingUnsubscribeCount = (await sent()).length;
    await action('rpcTestUnsubscribe');
    assert.equal((await sent()).length, pendingUnsubscribeCount);
    await update(selector, {slot: 12});
    await receive({jsonrpc: '2.0', id: rejected.id, error: {code: 1, message: 'retry'}});
    await update(selector, {slot: 13});
    await action('rpcTestUnsubscribe');
    const removed = (await sent()).at(-1);
    await reply(removed.id, true);
    const afterRemoval = (await events()).length;
    await update(selector, {slot: 14});
    await reply(removed.id, true);
    assert.equal((await events()).length, afterRemoval);
    await reply(extra.id, {extra: true});
    assert((await events()).some(value => value.label === 'update1' && value.status === 'Unsubscribed'));
    await receive({jsonrpc: '2.0', method: 'subscribeBestBlock', params: {
      subscription: 4294967295, error: 'stream ended',
    }});
    const afterTerminal = (await events()).length;
    await update(4294967295, {slot: 22});
    assert.equal((await events()).length, afterTerminal);
    assert.equal((await events()).at(-1).status, 'RemoteError');

    // Replacement connections detach even saved old event callbacks and settle pending work once.
    await action('rpcTestExtra');
    await page.evaluate(() => { globalThis.savedOldMessage = globalThis.rpcSockets.at(-1).onmessage; });
    const stale = (await sent()).at(-1);
    await opened();
    const closedCalls = (await events()).filter(value => value.label === 'extra' && value.status === 'ConnectionClosed');
    assert.equal(closedCalls.length, 1);
    assert.equal(closedCalls[0].id, stale.id);
    const afterReplacement = (await events()).length;
    await page.evaluate(id => globalThis.savedOldMessage({data: JSON.stringify({jsonrpc: '2.0', id, result: 'stale'})}), stale.id);
    assert.equal((await events()).length, afterReplacement);

    // A completion that opens a connection during cleanup wins without leaking an outer socket.
    await action('rpcTestOnClose');
    const socketsBefore = await page.evaluate(() => globalThis.rpcSockets.length);
    await opened();
    assert.equal(await page.evaluate(() => globalThis.rpcSockets.length), socketsBefore + 1);
    assert.equal((await events()).filter(value => value.label === 'close-reentrant' && value.status === 'ConnectionClosed').length, 1);

    // Fixed capacities reject excess work, and completed calls release slots for fresh requests.
    await action('rpcTestFill');
    let current = await sent();
    assert.equal(current.length, 16);
    assert.equal((await page.evaluate(() => globalThis.rpcAccepted.filter(value => value.label === 'bulk'))).filter(value => value.id === 0).length, 1);
    await reply(current.at(-1).id, 'complete');
    await action('rpcTestExtra');
    assert.equal((await sent()).length, 17);
    await opened();
    await action('rpcTestSubscriptions');
    current = await sent();
    assert.equal(current.length, 8);
    assert.equal((await page.evaluate(() => globalThis.rpcAccepted.filter(value => value.label === 'sub-limit'))).filter(value => value.id === 0).length, 1);
    for (const [index, request] of current.entries()) await reply(request.id, index + 100);
    await action('rpcTestExtra');
    assert.equal((await sent()).length, 9);
    const beforeRetirement = (await events()).length;
    await opened();
    const endedStreams = (await events()).slice(beforeRetirement).filter(value => value.label === 'update2' && value.status === 'ConnectionClosed');
    assert.equal(endedStreams.length, 8);
    assert.equal(new Set(endedStreams.map(value => value.id)).size, 8);

    // A subscribe timeout retires ambiguous remote state; delayed ACKs cannot create local streams.
    await action('rpcTestSubscriptionDeadline');
    await page.waitForFunction(() => globalThis.rpcEvents.at(-1)?.status === 'TimedOut');
    assert.equal(await page.evaluate(() => globalThis.rpcSockets.at(-1).readyState), 3);
    const afterTimeout = (await events()).length;
    await reply((await sent()).at(-1).id, 55);
    assert.equal((await events()).length, afterTimeout);

    // Duplicate subscription IDs are a protocol failure, never two callbacks attached to one ID.
    await action('rpcTestStart');
    await page.waitForFunction(() => globalThis.rpcSockets.at(-1).sent.length === 4);
    current = await sent();
    await reply(current[0].id, 77);
    await reply(current[1].id, 77);
    assert.equal((await events()).at(-1).status, 'InvalidResponse');
    assert.equal(await page.evaluate(() => globalThis.rpcSockets.at(-1).readyState), 3);
    assert.deepEqual(errors, []);
    assert.equal(await page.evaluate(() => globalThis.rpcTimers.size), 0);
    await writeFile(path.join(folder, 'rpc-client.json'), JSON.stringify({passed: true, events: await events(), errors}, null, 2));
    console.log('PASS concurrent browser calls, multiple subscriptions, routing, deadlines, capacity and reconnect cleanup');
  } finally {
    await page.close(); // Every failed assertion also retires its isolated runtime and socket handles.
  }
}

export async function checkLiveRpcClient(browser, root, folder, uiUrl, rpcUrl) {
  const page = await browser.newPage();
  const errors = [];
  const requests = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('websocket', socket => socket.on('framesent', ({payload}) => requests.push(JSON.parse(payload.toString()))));
  try {
    // Serve the compiled fixture in a normal UI origin; its WebSocket is the real native RPC server.
    await page.addInitScript(endpoint => {
      globalThis.rpcTestEndpoint = endpoint;
      globalThis.rpcEvents = [];
      globalThis.rpcAccepted = [];
    }, rpcUrl);
    const source = await readFile(path.join(root, 'build/tests/ui-rpc/rpc-test.js'), 'utf8');
    await page.route('**/app.js', route => route.fulfill({contentType: 'application/javascript', body: source}));
    await page.goto(uiUrl);
    await page.waitForFunction(() => ['ack1', 'ack2', 'update1', 'update2', 'first', 'second'].every(
      label => globalThis.rpcEvents.some(value => value.label === label && value.status === 'Success')));
    let events = await page.evaluate(() => globalThis.rpcEvents);
    const first = events.find(value => value.label === 'ack1').message.result;
    const second = events.find(value => value.label === 'ack2').message.result;
    assert.notEqual(first, second);
    assert.equal(events.find(value => value.label === 'update1').id, first);
    assert.equal(events.find(value => value.label === 'update2').id, second);
    assert.deepEqual(events.find(value => value.label === 'update1').message.params.result,
      events.find(value => value.label === 'update2').message.params.result);
    // Both commands go out before either completes, while the second subscription stays active.
    await page.evaluate(() => { rpcTestUnsubscribe(); rpcTestExtra(); });
    await page.waitForFunction(() => globalThis.rpcEvents.some(value => value.label === 'unsubscribe' && value.status === 'Success') &&
      globalThis.rpcEvents.some(value => value.label === 'extra' && value.status === 'Success'));
    await page.evaluate(() => rpcTestStop());
    events = await page.evaluate(() => globalThis.rpcEvents);
    assert.equal(events.filter(value => value.label === 'update1' && value.status === 'Unsubscribed').length, 1);
    assert.equal(events.filter(value => value.label === 'update2' && value.status === 'ConnectionClosed').length, 1);
    assert(!events.some(value => ['RemoteError', 'InvalidResponse', 'TimedOut', 'TransportError'].includes(value.status)));
    assert.deepEqual(errors, []);
    await writeFile(path.join(folder, 'rpc-live-subscriptions.json'), JSON.stringify({passed: true, events, requests, errors}, null, 2));
    console.log('PASS live browser subscriptions, interleaved clientInfo calls and unsubscribe cleanup');
  } finally {
    await page.close(); // The page owns the real browser socket even after an assertion fails.
  }
}
