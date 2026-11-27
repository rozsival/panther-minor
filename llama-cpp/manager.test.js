import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer as createHttpServer } from 'node:http';
import { createServer as createTcpServer } from 'node:net';
import test from 'node:test';

import {
  beginTrackedRequest,
  classifyRequest,
  endTrackedRequest,
  extractRequestedModel,
  fetchLoadedModels,
  fetchModelsList,
  getActiveProxyRequests,
  getModelInFlight,
  getModelsInFlight,
  isActive,
  prepareModelForInference,
  recordActivity,
  releaseModelReservation,
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
            { id: 'Qwen3.8-27B', status: { value: 'loaded' } },
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
    { body: JSON.stringify({ model: 'Qwen3.8-27B' }), method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
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

  const secondPromise = prepareModelForInference('Qwen3.8-27B', (url, options = {}) => {
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

  assert.equal(second, 'Qwen3.8-27B');
  assert.deepEqual(calls, [
    { method: 'GET', url: 'http://llama-cpp:8000/models' },
    { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  releaseModelReservation('Qwen3.8-27B');
});

test('prepareModelForInference stops waiting after DRAIN_TIMEOUT_SECONDS and drops the stale reservation', async () => {
  await withEnv('DRAIN_TIMEOUT_SECONDS', '0.1', async () => {
    resetActivityTracking();
    const calls = [];

    // A reservation nobody will ever release, like a request the manager lost track of.
    await prepareModelForInference(
      'Qwen3.6-35B-A3B',
      () => new Response(JSON.stringify({ data: [] }), { status: 200 })
    );
    assert.deepEqual(getModelsInFlight(), { 'Qwen3.6-35B-A3B': 1 });

    const startedAt = Date.now();
    const second = await prepareModelForInference('Qwen3.8-27B', (url, options = {}) => {
      calls.push({ method: options.method ?? 'GET', url: url.toString() });
      if (url.pathname === '/models') {
        return new Response(JSON.stringify({ data: [{ id: 'Qwen3.6-35B-A3B', status: { value: 'loaded' } }] }), {
          status: 200,
        });
      }
      return new Response(null, { status: 200 });
    });

    assert.equal(second, 'Qwen3.8-27B');
    assert.ok(Date.now() - startedAt < 2000, 'the switch must go ahead once the drain timeout passes');
    assert.deepEqual(calls, [
      { method: 'GET', url: 'http://llama-cpp:8000/models' },
      { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
    ]);
    assert.deepEqual(getModelsInFlight(), { 'Qwen3.8-27B': 1 });
    releaseModelReservation('Qwen3.8-27B');
  });
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

test('prepareModelForInference unloads only conflicting large models', async () => {
  resetActivityTracking();
  const calls = [];

  const reserved = await prepareModelForInference('Qwen3.8-27B', (url, options = {}) => {
    calls.push({ body: options.body, method: options.method ?? 'GET', url: url.toString() });

    if (url.pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'Qwen3.8-Flash-Next', status: { value: 'loaded' } },
            { id: 'Qwen3.5-2B', status: { value: 'loaded' } },
          ],
        }),
        { status: 200 }
      );
    }

    return new Response(null, { status: 200 });
  });

  assert.equal(reserved, 'Qwen3.8-27B');
  assert.deepEqual(calls, [
    { body: undefined, method: 'GET', url: 'http://llama-cpp:8000/models' },
    {
      body: JSON.stringify({ model: 'Qwen3.8-Flash-Next' }),
      method: 'POST',
      url: 'http://llama-cpp:8000/models/unload',
    },
  ]);
  assert.equal(getModelInFlight('Qwen3.8-27B'), 1);
  releaseModelReservation('Qwen3.8-27B');
});

test('prepareModelForInference waits for a conflicting model to drain before switching', async () => {
  resetActivityTracking();

  const first = await prepareModelForInference(
    'Qwen3.8-Flash-Next',
    () => new Response(JSON.stringify({ data: [] }), { status: 200 })
  );
  assert.equal(first, 'Qwen3.8-Flash-Next');
  assert.equal(getModelInFlight('Qwen3.8-Flash-Next'), 1);

  const calls = [];
  const secondPromise = prepareModelForInference('Qwen3.8-27B', (url, options = {}) => {
    calls.push({ method: options.method ?? 'GET', url: url.toString() });
    if (url.pathname === '/models') {
      return new Response(JSON.stringify({ data: [{ id: 'Qwen3.8-Flash-Next', status: { value: 'loaded' } }] }), {
        status: 200,
      });
    }
    return new Response(null, { status: 200 });
  });

  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(calls.length, 0);

  releaseModelReservation('Qwen3.8-Flash-Next');
  const second = await secondPromise;

  assert.equal(second, 'Qwen3.8-27B');
  assert.deepEqual(calls, [
    { method: 'GET', url: 'http://llama-cpp:8000/models' },
    { method: 'POST', url: 'http://llama-cpp:8000/models/unload' },
  ]);
  releaseModelReservation('Qwen3.8-27B');
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

test('classifyRequest arbitrates model loads as well as inference', () => {
  assert.equal(classifyRequest('POST', '/models/load'), 'model-load');
  assert.equal(classifyRequest('POST', '/v1/chat/completions'), 'inference');
  assert.equal(classifyRequest('POST', '/v1/completions'), 'inference');
  assert.equal(classifyRequest('POST', '/v1/embeddings'), 'embedding');
});

test('classifyRequest leaves catalogue reads and unloads unarbitrated', () => {
  assert.equal(classifyRequest('GET', '/models'), 'proxy');
  assert.equal(classifyRequest('GET', '/v1/models'), 'proxy');
  assert.equal(classifyRequest('GET', '/models/load'), 'proxy');
  assert.equal(classifyRequest('POST', '/models/unload'), 'proxy');
});

test('prepareModelForInference keeps an already loaded target resident', async () => {
  resetActivityTracking();
  const calls = [];
  const reserved = await prepareModelForInference('Qwen3.8-Flash-Next', (url, options = {}) => {
    calls.push({ body: options.body, method: options.method ?? 'GET', url: url.toString() });
    if (url.pathname === '/models') {
      return new Response(JSON.stringify({ data: [{ id: 'Qwen3.8-Flash-Next', status: { value: 'loaded' } }] }), {
        status: 200,
      });
    }
    return new Response(null, { status: 200 });
  });

  assert.equal(reserved, 'Qwen3.8-Flash-Next');
  assert.deepEqual(calls, [{ body: undefined, method: 'GET', url: 'http://llama-cpp:8000/models' }]);
  releaseModelReservation('Qwen3.8-Flash-Next');
});

// -- Proxy timeout, end to end ------------------------------------------------
// The manager reads LLAMA_SERVER_URL/PORT at module load, so these cases cannot
// use the in-process exports above: each spawns a real `node manager.js`
// against a fake llama-server on an ephemeral port.

// Fake llama-server: /models lists one loaded model; inference responses are
// delayed by `delayMs`, simulating a cold load or a wedged server.
function startFakeUpstream({ delayMs = 0 } = {}) {
  const sockets = new Set();
  const server = createHttpServer((req, res) => {
    if (req.url === '/models') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ data: [{ id: 'Qwen3.8-27B', status: { value: 'loaded' } }] }));
      return;
    }

    req.resume();
    req.on('end', () => {
      setTimeout(() => {
        if (res.writableEnded || res.destroyed) {
          return;
        }
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      }, delayMs);
    });
  });

  server.on('connection', (socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });

  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({
        // Destroying live sockets is required: a wedged request holds the
        // server open and server.close() alone would never settle.
        close: () => {
          for (const socket of sockets) {
            socket.destroy();
          }
          return new Promise((done) => server.close(done));
        },
        url: `http://127.0.0.1:${server.address().port}`,
      });
    });
  });
}

async function reserveFreePort() {
  const probe = createTcpServer();
  await new Promise((resolve) => probe.listen(0, '127.0.0.1', resolve));
  const { port } = probe.address();
  await new Promise((resolve) => probe.close(resolve));
  return port;
}

function startManagerProcess(env) {
  const child = spawn(process.execPath, ['manager.js'], {
    cwd: new URL('.', import.meta.url).pathname,
    env: { ...process.env, LOG_LEVEL: 'debug', ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let buffer = '';
  child.stdout.on('data', (chunk) => {
    buffer += chunk.toString();
  });
  child.stderr.on('data', (chunk) => {
    buffer += chunk.toString();
  });

  const ready = new Promise((resolve, reject) => {
    const check = () => {
      if (buffer.includes('server_started')) {
        resolve();
        return true;
      }
      return false;
    };
    child.stdout.on('data', check);
    child.once('exit', (code) => {
      if (!check()) {
        reject(new Error(`manager exited before ready (code ${code}): ${buffer}`));
      }
    });
    const timer = setTimeout(() => {
      if (!check()) {
        reject(new Error(`manager never became ready: ${buffer}`));
      }
    }, 10_000);
    timer.unref();
  });

  return { child, log: () => buffer, ready };
}

async function postInference(port, { timeoutMs } = {}) {
  const response = await fetch(`http://127.0.0.1:${port}/v1/chat/completions`, {
    body: JSON.stringify({ messages: [], model: 'Qwen3.8-27B' }),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
    ...(timeoutMs ? { signal: AbortSignal.timeout(timeoutMs) } : {}),
  });
  return { body: await response.text(), status: response.status };
}

test('proxied inference survives an upstream stall shorter than PROXY_TIMEOUT_SECONDS', async () => {
  const upstream = await startFakeUpstream({ delayMs: 1200 });
  const managerPort = await reserveFreePort();
  const { child, ready } = startManagerProcess({
    LLAMA_CPP_SLEEP_IDLE_SECONDS: '0',
    LLAMA_SERVER_URL: upstream.url,
    PORT: String(managerPort),
    PROXY_TIMEOUT_SECONDS: '5',
    UPSTREAM_TIMEOUT_SECONDS: '1',
  });

  try {
    await ready;
    const { status, body } = await postInference(managerPort);
    assert.equal(status, 200);
    assert.deepEqual(JSON.parse(body), { ok: true });
  } finally {
    child.kill('SIGKILL');
    await upstream.close();
  }
});

test('a wedged upstream is cut off by PROXY_TIMEOUT_SECONDS with 502, not held open forever', async () => {
  // Upstream answers after 30s; the manager's proxy timeout is 1s. The request
  // must fail at ~1s with 502 — proving the socket timeout actually fires and
  // destroys the connection (previously the option was inert and the request
  // would have completed at 30s).
  const upstream = await startFakeUpstream({ delayMs: 30_000 });
  const managerPort = await reserveFreePort();
  const { child, ready, log } = startManagerProcess({
    LLAMA_CPP_SLEEP_IDLE_SECONDS: '0',
    LLAMA_SERVER_URL: upstream.url,
    PORT: String(managerPort),
    PROXY_TIMEOUT_SECONDS: '1',
    UPSTREAM_TIMEOUT_SECONDS: '30',
  });

  try {
    await ready;
    const startedAt = Date.now();
    const { status } = await postInference(managerPort, { timeoutMs: 15_000 });
    const elapsedMs = Date.now() - startedAt;

    assert.equal(status, 502);
    assert.ok(elapsedMs < 10_000, `expected cutoff near the 1s proxy timeout, took ${elapsedMs}ms`);
    assert.match(log(), /proxy_upstream_timeout/u);
  } finally {
    child.kill('SIGKILL');
    await upstream.close();
  }
});

// -- Client hang-ups and upstream deaths, end to end -------------------------
// A reservation that outlives its request blocks every switch away from its
// model, so each way a request can end must release it.

// Fake llama-server driven per request by `onInference(req, res, model)`;
// /models reports `loadedModel` as loaded. Records every inference request.
function startScriptedUpstream({ loadedModel = 'Qwen3.8-Flash-Next', onInference }) {
  const sockets = new Set();
  const inferences = [];
  const server = createHttpServer((req, res) => {
    if (req.url === '/models') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ data: [{ id: loadedModel, status: { value: 'loaded' } }] }));
      return;
    }
    if (req.url === '/models/unload') {
      req.resume();
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end('{}');
      return;
    }

    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      const entry = { closedEarly: false, model: JSON.parse(body || '{}').model };
      inferences.push(entry);
      res.on('close', () => {
        entry.closedEarly = !res.writableFinished;
      });
      onInference(req, res, entry.model);
    });
  });

  server.on('connection', (socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });

  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({
        close: () => {
          for (const socket of sockets) {
            socket.destroy();
          }
          return new Promise((done) => server.close(done));
        },
        inferences,
        url: `http://127.0.0.1:${server.address().port}`,
      });
    });
  });
}

async function startManagerAgainst(upstream, env = {}) {
  const port = await reserveFreePort();
  const manager = startManagerProcess({
    LLAMA_CPP_SLEEP_IDLE_SECONDS: '0',
    LLAMA_SERVER_URL: upstream.url,
    PORT: String(port),
    PROXY_TIMEOUT_SECONDS: '30',
    UPSTREAM_TIMEOUT_SECONDS: '5',
    ...env,
  });
  await manager.ready;
  return { ...manager, port };
}

async function managerStatus(port) {
  return (await fetch(`http://127.0.0.1:${port}/status`)).json();
}

function waitFor(predicate, timeoutMs = 3000) {
  const deadline = Date.now() + timeoutMs;
  const poll = async () => {
    if (await predicate()) {
      return true;
    }
    if (Date.now() >= deadline) {
      return false;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
    return poll();
  };
  return poll();
}

function postModel(port, path, model, { signal } = {}) {
  return fetch(`http://127.0.0.1:${port}${path}`, {
    body: JSON.stringify({ messages: [], model }),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
    signal,
  });
}

for (const path of ['/v1/chat/completions', '/models/load']) {
  test(`a client hanging up on ${path} releases its reservation and cancels the upstream request`, async () => {
    // llama-server never answers: a cold load or a long prefill.
    const upstream = await startScriptedUpstream({
      onInference: () => {
        // Never answers.
      },
    });
    const { child, port } = await startManagerAgainst(upstream);

    try {
      const request = postModel(port, path, 'Qwen3.8-Flash-Next', { signal: AbortSignal.timeout(300) });
      await assert.rejects(request);

      assert.ok(
        await waitFor(async () => Object.keys((await managerStatus(port)).modelsInFlight).length === 0),
        'the reservation must be released as soon as the client hangs up'
      );
      assert.ok(
        await waitFor(() => upstream.inferences[0]?.closedEarly),
        'the upstream request must be closed so llama-server stops working on it'
      );
    } finally {
      child.kill('SIGKILL');
      await upstream.close();
    }
  });
}

test('a client that hangs up before a late, two-part upstream answer is still released', async () => {
  // The leak seen on the host: the client leaves first, then llama-server sends
  // its headers and, in a later write, the body. Before the fix no release
  // event fired at all, even after the upstream response had completed.
  const upstream = await startScriptedUpstream({
    onInference: (_req, res) => {
      setTimeout(() => {
        if (res.destroyed) {
          return;
        }
        res.writeHead(200, { 'content-length': '2', 'content-type': 'application/json' });
        res.flushHeaders();
        setTimeout(() => res.end('{}'), 100);
      }, 400);
    },
  });
  const { child, port } = await startManagerAgainst(upstream);

  try {
    await assert.rejects(
      postModel(port, '/v1/chat/completions', 'Qwen3.8-Flash-Next', { signal: AbortSignal.timeout(200) })
    );
    // Past the point where the upstream would have answered.
    await new Promise((resolve) => setTimeout(resolve, 800));
    assert.deepEqual((await managerStatus(port)).modelsInFlight, {});
  } finally {
    child.kill('SIGKILL');
    await upstream.close();
  }
});

test('a client that hangs up while queued behind a switch is never proxied', async () => {
  // Flash-Next's request holds the GPUs for 800ms; a 27B request queues behind it in the switch.
  const upstream = await startScriptedUpstream({
    onInference: (_req, res) => {
      setTimeout(() => {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end('{"ok":true}');
      }, 800);
    },
  });
  const { child, port, log } = await startManagerAgainst(upstream);

  try {
    const first = postModel(port, '/v1/chat/completions', 'Qwen3.8-Flash-Next');
    await waitFor(() => upstream.inferences.length === 1);
    const queued = postModel(port, '/v1/chat/completions', 'Qwen3.8-27B', { signal: AbortSignal.timeout(200) });
    await assert.rejects(queued);
    assert.equal((await first).status, 200);

    assert.ok(await waitFor(() => log().includes('client_gone_before_proxy')));
    assert.deepEqual((await managerStatus(port)).modelsInFlight, {});
    assert.deepEqual(
      upstream.inferences.map((entry) => entry.model),
      ['Qwen3.8-Flash-Next'],
      'nothing may reach llama-server for a client that is already gone'
    );
  } finally {
    child.kill('SIGKILL');
    await upstream.close();
  }
});

test('llama-server dying mid-stream ends the client response and releases the reservation', async () => {
  const upstream = await startScriptedUpstream({
    onInference: (_req, res) => {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write('data: {"n":0}\n\n');
      setTimeout(() => res.socket.destroy(), 100);
    },
  });
  const { child, port, log } = await startManagerAgainst(upstream);

  try {
    const response = await postModel(port, '/v1/chat/completions', 'Qwen3.8-Flash-Next', {
      signal: AbortSignal.timeout(5000),
    });
    const startedAt = Date.now();
    await assert.rejects(response.text(), (error) => error.name !== 'TimeoutError');
    assert.ok(Date.now() - startedAt < 2000, 'the client must see the stream break, not wait for its own timeout');

    assert.match(log(), /proxy_upstream_closed_mid_response/u);
    assert.deepEqual((await managerStatus(port)).modelsInFlight, {});
  } finally {
    child.kill('SIGKILL');
    await upstream.close();
  }
});
