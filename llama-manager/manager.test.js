// biome-ignore-all lint/performance/useTopLevelRegex: We don't need hoisted regexes for tests.
import assert from 'node:assert/strict';
import test from 'node:test';

import { isActive, recordActivity, resetActivityTracking } from './index.js';

test('isActive returns true when LLAMA_CPP_SLEEP_IDLE_SECONDS is 0 (disabled)', () => {
  // LLAMA_CPP_SLEEP_IDLE_SECONDS defaults to 0 in test env → always active
  resetActivityTracking();
  assert.ok(isActive());
});

test('recordActivity marks the server as active', () => {
  resetActivityTracking();
  // With SLEEP_IDLE_SECONDS=0, isActive() is always true regardless of activity
  recordActivity();
  assert.ok(isActive());
});

test('resetActivityTracking clears lastActivityAt', () => {
  recordActivity();
  resetActivityTracking();
  // With SLEEP_IDLE_SECONDS=0, still always active (disabled)
  assert.ok(isActive());
});
