import assert from 'node:assert/strict';
import test from 'node:test';

import {
  beginTrackedRequest,
  endTrackedRequest,
  extractRequestedModel,
  fetchLoadedModels,
  fetchModelsList,
  getActiveProxyRequests,
  getModelInFlight,
  isActive,
  prepareModelForInference,
  recordActivity,
  releaseModelReservation,
  resetActivityTracking,
  unloadIdleModels,
} from './manager.js';
import { isVariantOf } from './models.js';

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
  const models = await fetchLoadedModels(
    () =>
      new Response(
        JSON.stringify({
          data: [
            { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
            { id: 'panther-coder-large', status: { value: 'unloaded' } },
          ],
        }),
        { status: 200 }
      )
  );

  assert.deepEqual(models, [{ id: 'qwen35-35b-a3b-q8_0', status: 'loaded' }]);
});

test('extractRequestedModel returns model id from JSON request body', () => {
  assert.equal(extractRequestedModel(Buffer.from(JSON.stringify({ model: 'Qwen3.6-35B-A3' }))), 'Qwen3.6-35B-A3');
  assert.equal(extractRequestedModel(Buffer.from(JSON.stringify({ model: 123 }))), null);
  assert.equal(extractRequestedModel(Buffer.from('{invalid json')), null);
});

test('prepareModelForInference unloads a conflicting large model before reserving target', async () => {
  resetActivityTracking();
  const calls = [];

  const reserved = await prepareModelForInference('Qwen3.6-35B-A3B', (url, options = {}) => {
    calls.push({ body: options.body, method: options.method ?? 'GET', url: url.toString() });

    if (url.pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'Qwen3.6-27B', status: { value: 'loaded' } },
            { id: 'tiny-task-model', status: { value: 'loaded' } },
          ],
        }),
        { status: 200 }
      );
    }

    return new Response(null, { status: 200 });
  });

  assert.equal(reserved, 'Qwen3.6-35B-A3B');
  assert.deepEqual(calls, [
    { body: undefined, method: 'GET', url: 'http://llama-cpp:8000/models' },
    { body: JSON.stringify({ model: 'Qwen3.6-27B' }), method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  assert.equal(getModelInFlight('Qwen3.6-35B-A3B'), 1);
  releaseModelReservation('Qwen3.6-35B-A3B');
});

test('prepareModelForInference waits for conflicting large requests to drain', async () => {
  resetActivityTracking();
  const calls = [];

  const first = await prepareModelForInference(
    'Qwen3.6-35B-A3B',
    () => new Response(JSON.stringify({ data: [] }), { status: 200 })
  );
  assert.equal(first, 'Qwen3.6-35B-A3B');

  const secondPromise = prepareModelForInference('Qwen3.6-27B', (url, options = {}) => {
    calls.push({ method: options.method ?? 'GET', url: url.toString() });
    if (url.pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [{ id: 'Qwen3.6-35B-A3B', status: { value: 'loaded' } }],
        }),
        { status: 200 }
      );
    }
    return new Response(null, { status: 200 });
  });

  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(calls.length, 0);

  releaseModelReservation('Qwen3.6-35B-A3B');
  const second = await secondPromise;

  assert.equal(second, 'Qwen3.6-27B');
  assert.deepEqual(calls, [
    { method: 'GET', url: 'http://llama-cpp:8000/models' },
    { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  releaseModelReservation('Qwen3.6-27B');
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

test('isVariantOf detects reasoning/non-reasoning model pairs', () => {
  assert.ok(isVariantOf('Qwen3.5-2B-thinking', 'Qwen3.5-2B'));
  assert.ok(isVariantOf('Qwen3.5-2B', 'Qwen3.5-2B-thinking'));
  assert.ok(isVariantOf('Gemma-4-31B-thinking', 'Gemma-4-31B'));
  assert.ok(isVariantOf('  Qwen3.5-2B-thinking  ', 'Qwen3.5-2B'));
});

test('isVariantOf rejects non-variants and identical ids', () => {
  assert.equal(isVariantOf('Qwen3.5-2B', 'Qwen3.5-2B'), false);
  assert.equal(isVariantOf('Qwen3.5-2B', 'Gemma-4-31B'), false);
  assert.equal(isVariantOf('Qwen3.5-2B-thinking', 'Gemma-4-31B-thinking'), false);
  assert.equal(isVariantOf(null, 'Qwen3.5-2B'), false);
  assert.equal(isVariantOf('Qwen3.5-2B', undefined), false);
});

test('prepareModelForInference unloads only the sibling variant, not unrelated models', async () => {
  resetActivityTracking();
  const calls = [];

  const reserved = await prepareModelForInference('Qwen3.5-2B-thinking', (url, options = {}) => {
    calls.push({ body: options.body, method: options.method ?? 'GET', url: url.toString() });

    if (url.pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'Qwen3.5-2B', status: { value: 'loaded' } },
            { id: 'tiny-model', status: { value: 'loaded' } },
          ],
        }),
        { status: 200 }
      );
    }

    return new Response(null, { status: 200 });
  });

  assert.equal(reserved, 'Qwen3.5-2B-thinking');
  assert.deepEqual(calls, [
    { body: undefined, method: 'GET', url: 'http://llama-cpp:8000/models' },
    { body: JSON.stringify({ model: 'Qwen3.5-2B' }), method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  assert.equal(getModelInFlight('Qwen3.5-2B-thinking'), 1);
  releaseModelReservation('Qwen3.5-2B-thinking');
});

test('prepareModelForInference waits for a loaded variant to drain before switching', async () => {
  resetActivityTracking();

  const first = await prepareModelForInference(
    'Qwen3.5-2B',
    () => new Response(JSON.stringify({ data: [] }), { status: 200 })
  );
  assert.equal(first, 'Qwen3.5-2B');
  assert.equal(getModelInFlight('Qwen3.5-2B'), 1);

  const calls = [];
  const secondPromise = prepareModelForInference('Qwen3.5-2B-thinking', (url, options = {}) => {
    calls.push({ method: options.method ?? 'GET', url: url.toString() });
    if (url.pathname === '/models') {
      return new Response(JSON.stringify({ data: [{ id: 'Qwen3.5-2B', status: { value: 'loaded' } }] }), {
        status: 200,
      });
    }
    return new Response(null, { status: 200 });
  });

  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(calls.length, 0);

  releaseModelReservation('Qwen3.5-2B');
  const second = await secondPromise;

  assert.equal(second, 'Qwen3.5-2B-thinking');
  assert.deepEqual(calls, [
    { method: 'GET', url: 'http://llama-cpp:8000/models' },
    { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  releaseModelReservation('Qwen3.5-2B-thinking');
});

test('prepareModelForInference reserves the target without unloading when nothing conflicts', async () => {
  resetActivityTracking();
  const calls = [];

  const reserved = await prepareModelForInference('Qwen3.5-2B', (url, options = {}) => {
    calls.push({ method: options.method ?? 'GET', url: url.toString() });
    if (url.pathname === '/models') {
      return new Response(JSON.stringify({ data: [{ id: 'tiny-model', status: { value: 'loaded' } }] }), {
        status: 200,
      });
    }
    return new Response(null, { status: 200 });
  });

  assert.equal(reserved, 'Qwen3.5-2B');
  assert.deepEqual(calls, [{ method: 'GET', url: 'http://llama-cpp:8000/models' }]);
  assert.equal(getModelInFlight('Qwen3.5-2B'), 1);
  releaseModelReservation('Qwen3.5-2B');
});

test('prepareModelForInference returns null and makes no upstream calls for a missing model id', async () => {
  resetActivityTracking();
  let called = false;
  const reserved = await prepareModelForInference(null, () => {
    called = true;
    return new Response(null, { status: 200 });
  });
  assert.equal(reserved, null);
  assert.equal(called, false);
});
