// biome-ignore-all lint/performance/useTopLevelRegex: We don't need hoisted regexes for tests.
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  beginTrackedRequest,
  endTrackedRequest,
  extractRequestedModel,
  fetchLoadedModels,
  fetchModelsList,
  getActiveProxyRequests,
  getLargeModelInFlight,
  isActive,
  prepareLargeModelForInference,
  recordActivity,
  releaseLargeModelReservation,
  resetActivityTracking,
  unloadIdleModels,
} from './manager.js';
import { isLargeModelId, LARGE_MODEL_IDS } from './models.js';

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

test('large model list lives in models.js', () => {
  assert.deepEqual(LARGE_MODEL_IDS, ['Qwen3.5-35B-A3', 'Qwen3.5-27B', 'Gemma-4-26B-A4B', 'Gemma-4-31B']);
  assert.equal(isLargeModelId('Qwen3.5-35B-A3'), true);
  assert.equal(isLargeModelId('panther-coder-large'), false);
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

test('extractRequestedModel returns model id from JSON request body', () => {
  assert.equal(extractRequestedModel(Buffer.from(JSON.stringify({ model: 'Qwen3.5-35B-A3' }))), 'Qwen3.5-35B-A3');
  assert.equal(extractRequestedModel(Buffer.from(JSON.stringify({ model: 123 }))), null);
  assert.equal(extractRequestedModel(Buffer.from('{invalid json')), null);
});

test('prepareLargeModelForInference unloads conflicting loaded large model before reserving target', async () => {
  const calls = [];

  const reservation = await prepareLargeModelForInference('Qwen3.5-35B-A3', (url, options = {}) => {
    calls.push({ method: options.method ?? 'GET', url: url.toString() });

    if (url.pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'Qwen3.5-27B', status: { value: 'loaded' } },
            { id: 'tiny-task-model', status: { value: 'loaded' } },
          ],
        }),
        { status: 200 }
      );
    }

    assert.equal(url.pathname, '/models/unload');
    assert.equal(options.body, JSON.stringify({ model: 'Qwen3.5-27B' }));
    return new Response(null, { status: 200 });
  });

  assert.deepEqual(reservation, {
    trackedLargeModelId: 'Qwen3.5-35B-A3',
    unloadedModels: ['Qwen3.5-27B'],
  });
  assert.deepEqual(calls, [
    { method: 'GET', url: 'http://llama-cpp:8000/models' },
    { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  assert.equal(getLargeModelInFlight('Qwen3.5-35B-A3'), 1);
  releaseLargeModelReservation('Qwen3.5-35B-A3');
});

test('prepareLargeModelForInference waits for conflicting large requests to drain', async () => {
  const calls = [];

  const firstReservation = await prepareLargeModelForInference('Qwen3.5-35B-A3', () => {
    return new Response(JSON.stringify({ data: [] }), { status: 200 });
  });

  const secondReservationPromise = prepareLargeModelForInference('Qwen3.5-27B', (url, options = {}) => {
    calls.push({ method: options.method ?? 'GET', url: url.toString() });
    if (url.pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [{ id: 'Qwen3.5-35B-A3', status: { value: 'loaded' } }],
        }),
        { status: 200 }
      );
    }
    return new Response(null, { status: 200 });
  });

  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(calls.length, 0);

  releaseLargeModelReservation(firstReservation.trackedLargeModelId);
  const secondReservation = await secondReservationPromise;

  assert.deepEqual(secondReservation, {
    trackedLargeModelId: 'Qwen3.5-27B',
    unloadedModels: ['Qwen3.5-35B-A3'],
  });
  assert.deepEqual(calls, [
    { method: 'GET', url: 'http://llama-cpp:8000/models' },
    { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  releaseLargeModelReservation(secondReservation.trackedLargeModelId);
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
