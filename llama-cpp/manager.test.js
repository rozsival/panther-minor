// biome-ignore-all lint/performance/useTopLevelRegex: We don't need hoisted regexes for tests.
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  beginTrackedRequest,
  endTrackedRequest,
  fetchLoadedModels,
  fetchModelsList,
  getActiveProxyRequests,
  isActive,
  recordActivity,
  resetActivityTracking,
  unloadIdleModels,
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

test('isActive returns true when LLAMA_CPP_SLEEP_IDLE_SECONDS is 0 (disabled)', async () => {
  await withEnv('LLAMA_CPP_SLEEP_IDLE_SECONDS', '0', () => {
    resetActivityTracking();
    assert.ok(isActive());
  });
});

test('recordActivity marks the server as active in idle mode', async () => {
  await withEnv('LLAMA_CPP_SLEEP_IDLE_SECONDS', '1', () => {
    resetActivityTracking();
    recordActivity();
    assert.ok(isActive());
  });
});

test('tracked proxy requests keep the manager active until the response closes', async () => {
  await withEnv('LLAMA_CPP_SLEEP_IDLE_SECONDS', '1', () => {
    resetActivityTracking();
    beginTrackedRequest();
    assert.equal(getActiveProxyRequests(), 1);
    assert.ok(isActive());

    endTrackedRequest();
    assert.equal(getActiveProxyRequests(), 0);
    assert.equal(isActive(), false);
  });
});

test('fetchModelsList reads /models and excludes embedding models', async () => {
  const models = await fetchModelsList((url) => {
    assert.equal(url.toString(), 'http://llama-cpp:8000/models');
    return new Response(
      JSON.stringify({
        data: [
          { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
          { id: 'qwen3-embedding-0-6b-q8_0', status: { value: 'loaded' } },
          { id: 'panther-coder-large', status: { value: 'unloaded' } },
        ],
      }),
      { status: 200 }
    );
  });

  assert.deepEqual(models, [
    { id: 'qwen35-35b-a3b-q8_0', status: 'loaded' },
    { id: 'panther-coder-large', status: 'unloaded' },
  ]);
});

test('fetchLoadedModels returns only loaded models', async () => {
  const models = await fetchLoadedModels(() => {
    return new Response(
      JSON.stringify({
        data: [
          { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
          { id: 'panther-coder-large', status: { value: 'unloaded' } },
        ],
      }),
      { status: 200 }
    );
  });

  assert.deepEqual(models, [{ id: 'qwen35-35b-a3b-q8_0', status: 'loaded' }]);
});

test('unloadIdleModels unloads every loaded model via /models/unload', async () => {
  await withEnv('LLAMA_CPP_SLEEP_IDLE_SECONDS', '1', async () => {
    resetActivityTracking();
    const calls = [];

    const unloadedModels = await unloadIdleModels((url, options = {}) => {
      calls.push({ options, url: url.toString() });

      if (url.pathname === '/models') {
        return new Response(
          JSON.stringify({
            data: [
              { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
              { id: 'panther-coder-large', status: { value: 'loaded' } },
              { id: 'text-embedding-3-small', status: { value: 'loaded' } },
            ],
          }),
          { status: 200 }
        );
      }

      assert.equal(url.pathname, '/models/unload');
      assert.equal(options.method, 'POST');
      return new Response(null, { status: 200 });
    });

    assert.deepEqual(unloadedModels, ['qwen35-35b-a3b-q8_0', 'panther-coder-large']);
    assert.deepEqual(
      calls.map((call) => call.url),
      ['http://llama-cpp:8000/models', 'http://llama-cpp:8000/models/unload', 'http://llama-cpp:8000/models/unload']
    );
    assert.deepEqual(
      calls.slice(1).map((call) => JSON.parse(call.options.body)),
      [{ model: 'qwen35-35b-a3b-q8_0' }, { model: 'panther-coder-large' }]
    );
  });
});
