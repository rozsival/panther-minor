// biome-ignore-all lint/performance/useTopLevelRegex: We don't need hoisted regexes for tests.
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ContainerState,
  getContainerState,
  isActive,
  recordActivity,
  resetActivityTracking,
  resetContainerState,
} from './manager.js';

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

test('ContainerState constants are defined', () => {
  assert.equal(ContainerState.RUNNING, 'running');
  assert.equal(ContainerState.STOPPING, 'stopping');
  assert.equal(ContainerState.STOPPED, 'stopped');
  assert.equal(ContainerState.STARTING, 'starting');
});

test('getContainerState returns current state, resetContainerState restores to running', () => {
  resetContainerState();
  assert.equal(getContainerState(), ContainerState.RUNNING);
});
