import { createServer, request as httpRequest } from 'node:http';
import { normalizeModelsPayload } from './models.js';

const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '8000', 10);
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');
const LOG_LEVEL = (process.env.LOG_LEVEL ?? 'info').toLowerCase();
const IDLE_UNLOAD_RETRY_SECONDS = Number.parseFloat(process.env.IDLE_UNLOAD_RETRY_SECONDS ?? '15');

const LOG_PRIORITY = {
  debug: 3,
  error: 0,
  info: 2,
  warn: 1,
};

function shouldLog(level) {
  return (LOG_PRIORITY[level] ?? LOG_PRIORITY.info) <= (LOG_PRIORITY[LOG_LEVEL] ?? LOG_PRIORITY.info);
}

function log(level, message, fields = undefined) {
  if (!shouldLog(level)) {
    return;
  }

  const base = `[llama-manager] ${level.toUpperCase()} ${message}`;
  if (!fields || Object.keys(fields).length === 0) {
    console.log(base);
    return;
  }

  const context = Object.entries(fields)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  console.log(`${base} ${context}`);
}

// -- Activity tracking --------------------------------------------------------

// Initialise to now so the idle window starts from process startup, not epoch.
let lastActivityAt = Date.now();
let activeProxyRequests = 0;
let unloadInProgress = false;
let idleTimer = null;

function getIdleTimeoutSeconds() {
  return Number.parseFloat(process.env.LLAMA_CPP_SLEEP_IDLE_SECONDS ?? '0');
}

function isIdleModeEnabled() {
  return getIdleTimeoutSeconds() > 0;
}

export function recordActivity() {
  const wasActive = isActive();
  lastActivityAt = Date.now();
  if (!wasActive) {
    log('info', 'inference_activity_detected');
  }
  scheduleIdleCheck();
}

export function isActive() {
  if (activeProxyRequests > 0) {
    return true;
  }
  if (!isIdleModeEnabled()) {
    return true;
  }
  return Date.now() - lastActivityAt < getIdleTimeoutSeconds() * 1000;
}

export function resetActivityTracking() {
  lastActivityAt = 0;
  activeProxyRequests = 0;
  unloadInProgress = false;
  if (idleTimer) {
    clearTimeout(idleTimer);
    idleTimer = null;
  }
}

export function beginTrackedRequest() {
  activeProxyRequests += 1;
  if (idleTimer) {
    clearTimeout(idleTimer);
    idleTimer = null;
  }
}

export function endTrackedRequest() {
  activeProxyRequests = Math.max(0, activeProxyRequests - 1);
  scheduleIdleCheck();
}

export function getActiveProxyRequests() {
  return activeProxyRequests;
}

function scheduleIdleCheck() {
  if (!isIdleModeEnabled() || activeProxyRequests > 0) {
    return;
  }
  if (idleTimer) {
    clearTimeout(idleTimer);
  }

  const elapsed = Date.now() - lastActivityAt;
  const delay = Math.max(0, getIdleTimeoutSeconds() * 1000 - elapsed);

  idleTimer = setTimeout(() => {
    idleTimer = null;
    if (!isActive()) {
      unloadIdleModels().catch((error) => {
        log('error', 'idle_unload_failed', { error: error?.message ?? String(error) });
      });
    }
  }, delay + 100);
}

function scheduleUnloadRetry() {
  if (!isIdleModeEnabled() || isActive()) {
    return;
  }
  if (idleTimer) {
    clearTimeout(idleTimer);
  }
  idleTimer = setTimeout(() => {
    idleTimer = null;
    unloadIdleModels().catch((error) => {
      log('error', 'idle_unload_retry_failed', { error: error?.message ?? String(error) });
    });
  }, IDLE_UNLOAD_RETRY_SECONDS * 1000);
}

async function fetchJson(pathname, fetchImpl = fetch) {
  const url = new URL(`${LLAMA_SERVER_URL}${pathname}`);
  const response = await fetchImpl(url, {
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
  });

  if (!response.ok) {
    const error = new Error(`upstream json request failed: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
  }

  return response.json();
}

async function postJson(pathname, body, fetchImpl = fetch) {
  const url = new URL(`${LLAMA_SERVER_URL}${pathname}`);
  const response = await fetchImpl(url, {
    body: JSON.stringify(body),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
  });

  if (!response.ok) {
    const error = new Error(`upstream post request failed: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
  }
}

export async function fetchModelsList(fetchImpl = fetch) {
  return normalizeModelsPayload(await fetchJson('/models', fetchImpl));
}

export async function fetchLoadedModels(fetchImpl = fetch) {
  return (await fetchModelsList(fetchImpl)).filter((model) => model.status === 'loaded');
}

export async function unloadModel(modelId, fetchImpl = fetch) {
  await postJson('/models/unload', { model: modelId }, fetchImpl);
}

export async function unloadIdleModels(fetchImpl = fetch) {
  if (!isIdleModeEnabled() || isActive() || unloadInProgress) {
    return [];
  }

  unloadInProgress = true;
  try {
    const loadedModels = await fetchLoadedModels(fetchImpl);
    if (loadedModels.length === 0) {
      log('debug', 'idle_unload_skipped_no_loaded_models');
      return [];
    }

    const unloadedModels = [];
    for (const model of loadedModels) {
      if (isActive()) {
        log('info', 'idle_unload_cancelled_activity_resumed', {
          unloadedModels,
        });
        scheduleIdleCheck();
        return unloadedModels;
      }

      await unloadModel(model.id, fetchImpl);
      unloadedModels.push(model.id);
    }

    log('info', 'idle_unload_complete', {
      count: unloadedModels.length,
      models: unloadedModels,
    });
    return unloadedModels;
  } catch (error) {
    log('warn', 'idle_unload_retry_scheduled', {
      error: error?.message ?? String(error),
      retrySeconds: IDLE_UNLOAD_RETRY_SECONDS,
    });
    scheduleUnloadRetry();
    throw error;
  } finally {
    unloadInProgress = false;
  }
}

// -- Hop-by-hop headers -------------------------------------------------------

// Hop-by-hop headers must not be forwarded (they are connection-specific).
const hopByHopHeaders = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

function stripHopByHopHeaders(headers) {
  const result = {};
  for (const [key, value] of Object.entries(headers)) {
    if (!hopByHopHeaders.has(key.toLowerCase())) {
      result[key] = value;
    }
  }
  return result;
}

// -- Proxy --------------------------------------------------------------------

const upstreamBase = new URL(LLAMA_SERVER_URL);

function proxyToUpstream(req, res, options = {}) {
  const trackRequest = options.trackRequest === true;
  let trackedRequestFinished = false;

  const finishTrackedRequest = () => {
    if (!trackRequest || trackedRequestFinished) {
      return;
    }
    trackedRequestFinished = true;
    endTrackedRequest();
  };

  if (trackRequest) {
    beginTrackedRequest();
  }

  const proxyReq = httpRequest(
    {
      hostname: upstreamBase.hostname,
      port: Number(upstreamBase.port) || 80,
      path: req.url,
      method: req.method,
      headers: { ...stripHopByHopHeaders(req.headers), host: upstreamBase.host },
      timeout: UPSTREAM_TIMEOUT_SECONDS * 1000,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode, stripHopByHopHeaders(proxyRes.headers));
      proxyRes.pipe(res);
      res.on('finish', finishTrackedRequest);
      res.on('close', () => {
        proxyRes.destroy();
        proxyReq.destroy();
        finishTrackedRequest();
      });
      proxyRes.on('end', finishTrackedRequest);
      proxyRes.on('error', finishTrackedRequest);
    }
  );

  req.pipe(proxyReq);

  proxyReq.on('error', (error) => {
    finishTrackedRequest();
    log('warn', 'proxy_upstream_error', { error: error.message, path: req.url });
    if (!res.headersSent) {
      res.writeHead(502);
      res.end('Bad Gateway\n');
    }
  });

  req.on('aborted', finishTrackedRequest);
}

// -- HTTP server --------------------------------------------------------------

const activityPaths = new Set(['/models', '/v1/models']);
const embeddingPaths = new Set(['/v1/embeddings']);
const inferencePaths = new Set(['/v1/chat/completions', '/v1/completions']);

export function startServer() {
  const server = createServer((req, res) => {
    const requestPath = (req.url ?? '/').split('?')[0];

    if (requestPath === '/health') {
      log('debug', 'health_request');
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('ok\n');
      return;
    }

    if (requestPath === '/status') {
      log('debug', 'status_request');
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          active: isActive(),
          activeProxyRequests,
          idleTimeoutSeconds: getIdleTimeoutSeconds(),
          unloadInProgress,
        })
      );
      return;
    }

    const trackRequest = req.method === 'POST' && (inferencePaths.has(requestPath) || embeddingPaths.has(requestPath));

    if (trackRequest) {
      recordActivity();
    } else if (activityPaths.has(requestPath)) {
      recordActivity();
    }

    proxyToUpstream(req, res, { trackRequest });
  });

  server.listen(PORT, '0.0.0.0', () => {
    log('info', 'server_started', {
      idleSeconds: getIdleTimeoutSeconds(),
      idleUnloadRetrySeconds: IDLE_UNLOAD_RETRY_SECONDS,
      listen: `0.0.0.0:${PORT}`,
      logLevel: LOG_LEVEL,
      timeoutSeconds: UPSTREAM_TIMEOUT_SECONDS,
      upstream: LLAMA_SERVER_URL,
    });
    scheduleIdleCheck();
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
