// Self-check for the pure decision logic in app.js. Run: node test.mjs
// Not copied into the image — see docker/Dockerfile.

import assert from 'node:assert/strict';
import {
  FAIL_LIMIT,
  collapsedIds,
  pickPipMain,
  probeStatus,
  shouldReload,
  slideshowOrder,
} from './app.js';

const cam = (id, over = {}) => ({
  id,
  enabled: true,
  status: 'online',
  fails: 0,
  ...over,
});

// --- probeStatus ---------------------------------------------------------

assert.equal(probeStatus(false, 0), 'offline');
assert.equal(probeStatus(true, 12), 'online');
assert.equal(probeStatus(true, 300), 'degraded');

// --- collapsedIds --------------------------------------------------------

assert.deepEqual(
  collapsedIds([cam('a'), cam('b', { enabled: false })], true),
  ['b'],
  'a switched-off camera collapses immediately',
);

assert.deepEqual(
  collapsedIds([cam('a'), cam('b', { status: 'offline', fails: FAIL_LIMIT - 1 })], true),
  [],
  'one failed probe is not enough — no reflow on a single dropped packet',
);

assert.deepEqual(
  collapsedIds([cam('a'), cam('b', { status: 'offline', fails: FAIL_LIMIT })], true),
  ['b'],
  'collapses once the failures reach the limit',
);

assert.deepEqual(
  collapsedIds([cam('a', { status: 'unknown' }), cam('b', { status: 'unknown' })], true),
  [],
  'the pre-first-probe state never collapses anything',
);

assert.deepEqual(
  collapsedIds([cam('a', { enabled: false }), cam('b', { status: 'offline', fails: 9 })], true),
  [],
  'all cameras dead: collapse nothing rather than show an empty page',
);

assert.deepEqual(
  collapsedIds([cam('a'), cam('b', { enabled: false })], false),
  [],
  'the toolbar toggle switches the whole behaviour off',
);

// --- pickPipMain ---------------------------------------------------------

const three = [cam('a'), cam('b'), cam('c', { status: 'offline', fails: FAIL_LIMIT })];

assert.equal(pickPipMain(three, ['c'], 'b'), 'b', 'a promoted camera keeps the main slot');
assert.equal(pickPipMain(three, ['c'], 'c'), 'a', 'a collapsed favourite falls back to first live');
assert.equal(pickPipMain(three, ['c'], null), 'a', 'no favourite: first live camera');
assert.equal(
  pickPipMain([cam('a', { status: 'offline' }), cam('b', { status: 'offline' })], [], null),
  'a',
  'nothing live: still show something',
);
assert.equal(pickPipMain([], [], null), null);
assert.equal(pickPipMain([cam('a')], ['a'], null), null, 'everything collapsed: no main slot');

// --- slideshowOrder ------------------------------------------------------

assert.deepEqual(
  slideshowOrder([cam('a'), cam('b', { status: 'offline' }), cam('c', { enabled: false })]),
  ['a'],
  'skips offline and disabled cameras',
);

assert.deepEqual(
  slideshowOrder([cam('a', { status: 'offline' }), cam('b', { status: 'offline' })]),
  ['a', 'b'],
  'nothing live: falls back to every enabled camera instead of dead-ending',
);

assert.deepEqual(slideshowOrder([cam('a', { enabled: false })]), [], 'disabled stays out');

// --- shouldReload --------------------------------------------------------

assert.equal(shouldReload('offline', 'online'), true, 'the bug this all started with');
assert.equal(shouldReload('offline', 'degraded'), true);
assert.equal(shouldReload('offline', 'offline'), false);
assert.equal(shouldReload('online', 'online'), false, 'never restart a working stream');
assert.equal(shouldReload('unknown', 'online'), false, 'first probe: the iframe is already loading');

console.log('ok');
