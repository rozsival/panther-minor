import assert from 'node:assert/strict';
import test from 'node:test';

import {
  beginTrackedRequest,
  endTrackedRequest,
  getActiveProxyRequests,
  isActive,
  recordActivity,
  resetActivityTracking,
} from './manager.js';

async function withEnv(name, value, callback) {
  const previous = process.env[name];
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }

  const restore = () => {
    if (previous === undefined) {
      delete process.env[name];
      return;
    }
    process.env[name] = previous;
  };

  try {
    return await callback();
  } finally {
    restore();
  }
}

test('isActive returns true when SD_CPP_SLEEP_IDLE_SECONDS is 0 (disabled)', async () => {
  await withEnv('SD_CPP_SLEEP_IDLE_SECONDS', '0', () => {
    resetActivityTracking();
    assert.ok(isActive());
  });
});

test('recordActivity marks the server as active in idle mode', async () => {
  await withEnv('SD_CPP_SLEEP_IDLE_SECONDS', '1', () => {
    resetActivityTracking();
    recordActivity();
    assert.ok(isActive());
  });
});

test('tracked proxy requests keep the manager active until the response closes', async () => {
  await withEnv('SD_CPP_SLEEP_IDLE_SECONDS', '1', () => {
    resetActivityTracking();
    beginTrackedRequest();
    assert.equal(getActiveProxyRequests(), 1);
    assert.ok(isActive());

    endTrackedRequest();
    assert.equal(getActiveProxyRequests(), 0);
    assert.equal(isActive(), false);
  });
});

test('endTrackedRequest never drops the in-flight counter below zero', () => {
  resetActivityTracking();
  endTrackedRequest();
  assert.equal(getActiveProxyRequests(), 0);
});
