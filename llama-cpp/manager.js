import { createServer, request as httpRequest } from 'node:http';

const LLAMA_CPP_CONTAINER = process.env.LLAMA_CPP_CONTAINER_NAME ?? 'llama-cpp';
const LLAMA_CPP_SLEEP_IDLE_SECONDS = Number.parseFloat(process.env.LLAMA_CPP_SLEEP_IDLE_SECONDS ?? '0');
const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '8000', 10);
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');
const LOG_LEVEL = (process.env.LOG_LEVEL ?? 'info').toLowerCase();

// Scale-to-zero is only active when an idle timeout is configured.
const SCALE_TO_ZERO = LLAMA_CPP_SLEEP_IDLE_SECONDS > 0;

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

export function recordActivity() {
  const wasActive = isActive();
  lastActivityAt = Date.now();
  if (!wasActive) {
    log('info', 'inference_activity_detected');
  }
  if (SCALE_TO_ZERO && containerState === ContainerState.RUNNING) {
    scheduleIdleCheck();
  }
}

export function isActive() {
  if (LLAMA_CPP_SLEEP_IDLE_SECONDS <= 0) {
    return true;
  }
  return Date.now() - lastActivityAt < LLAMA_CPP_SLEEP_IDLE_SECONDS * 1000;
}

export function resetActivityTracking() {
  lastActivityAt = 0;
}

// -- Container state machine --------------------------------------------------

export const ContainerState = {
  RUNNING: 'running',
  STOPPING: 'stopping',
  STOPPED: 'stopped',
  STARTING: 'starting',
};

let containerState = ContainerState.RUNNING;
let pendingRequests = [];
let idleTimer = null;

export function getContainerState() {
  return containerState;
}

export function resetContainerState() {
  containerState = ContainerState.RUNNING;
  pendingRequests = [];
  if (idleTimer) {
    clearTimeout(idleTimer);
    idleTimer = null;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function scheduleIdleCheck() {
  if (!SCALE_TO_ZERO || containerState !== ContainerState.RUNNING) {
    return;
  }
  if (idleTimer) {
    clearTimeout(idleTimer);
  }

  const elapsed = Date.now() - lastActivityAt;
  const remaining = Math.max(0, LLAMA_CPP_SLEEP_IDLE_SECONDS * 1000 - elapsed);

  idleTimer = setTimeout(() => {
    idleTimer = null;
    if (!isActive() && containerState === ContainerState.RUNNING) {
      stopContainer().catch(console.error);
    }
  }, remaining + 100);
}

// -- Docker API ---------------------------------------------------------------

function dockerRequest(method, path) {
  return new Promise((resolve, reject) => {
    const req = httpRequest(
      {
        socketPath: '/var/run/docker.sock',
        method,
        path,
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => resolve({ status: res.statusCode, body }));
      }
    );
    req.on('error', reject);
    req.end();
  });
}

async function syncContainerState() {
  if (!SCALE_TO_ZERO) {
    return;
  }
  try {
    const result = await dockerRequest('GET', `/containers/${LLAMA_CPP_CONTAINER}/json`);
    if (result.status === 200) {
      const info = JSON.parse(result.body);
      containerState = info.State?.Running ? ContainerState.RUNNING : ContainerState.STOPPED;
      log('info', 'startup_container_state_synced', { container: LLAMA_CPP_CONTAINER, state: containerState });
    }
  } catch (error) {
    log('warn', 'startup_container_state_sync_failed', { error: error?.message ?? String(error) });
  }
  if (containerState === ContainerState.RUNNING) {
    scheduleIdleCheck();
  }
}

async function stopContainer() {
  if (containerState !== ContainerState.RUNNING) {
    return;
  }
  containerState = ContainerState.STOPPING;
  log('info', 'container_stopping', { container: LLAMA_CPP_CONTAINER });

  try {
    await dockerRequest('POST', `/containers/${LLAMA_CPP_CONTAINER}/stop`);
    containerState = ContainerState.STOPPED;
    log('info', 'container_stopped', { container: LLAMA_CPP_CONTAINER });
  } catch (error) {
    log('error', 'container_stop_failed', { error: error?.message ?? String(error) });
    containerState = ContainerState.RUNNING;
    scheduleIdleCheck();
    return;
  }

  // If requests arrived while we were stopping, start back up immediately.
  if (pendingRequests.length > 0) {
    startContainer().catch(console.error);
  }
}

async function startContainer() {
  if (containerState !== ContainerState.STOPPED) {
    return;
  }
  containerState = ContainerState.STARTING;
  log('info', 'container_starting', { container: LLAMA_CPP_CONTAINER });

  try {
    await dockerRequest('POST', `/containers/${LLAMA_CPP_CONTAINER}/start`);
    log('info', 'container_start_requested', { container: LLAMA_CPP_CONTAINER });
    await waitForHealthy();
    containerState = ContainerState.RUNNING;
    log('info', 'container_running', { container: LLAMA_CPP_CONTAINER });
    scheduleIdleCheck();
    drainQueue();
  } catch (error) {
    log('error', 'container_start_failed', { error: error?.message ?? String(error) });
    containerState = ContainerState.STOPPED;
    for (const { res } of pendingRequests) {
      if (!res.headersSent) {
        res.writeHead(503);
        res.end('Service Unavailable\n');
      }
    }
    pendingRequests = [];
  }
}

async function waitForHealthy() {
  const maxAttempts = 60;
  const intervalMs = 2000;
  const upstreamBase = new URL(LLAMA_SERVER_URL);

  log('info', 'container_health_polling_start', {
    maxWaitSeconds: (maxAttempts * intervalMs) / 1000,
  });

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await sleep(intervalMs);
    const healthy = await new Promise((resolve) => {
      const req = httpRequest(
        {
          hostname: upstreamBase.hostname,
          port: Number(upstreamBase.port) || 80,
          path: '/health',
          method: 'GET',
          timeout: 3000,
        },
        (res) => resolve(res.statusCode === 200)
      );
      req.on('error', () => resolve(false));
      req.on('timeout', () => {
        req.destroy();
        resolve(false);
      });
      req.end();
    });

    if (healthy) {
      log('info', 'container_healthy', { attempt });
      return;
    }
    log('debug', 'container_not_yet_healthy', { attempt });
  }

  throw new Error(`container did not become healthy after ${(maxAttempts * intervalMs) / 1000}s`);
}

function drainQueue() {
  const queued = pendingRequests.splice(0);
  if (queued.length > 0) {
    log('info', 'queue_drained', { count: queued.length });
  }
  for (const { req, res } of queued) {
    proxyToUpstream(req, res);
  }
}

// -- Hop-by-hop headers -------------------------------------------------------

// Hop-by-hop headers must not be forwarded (they are connection-specific).
const HOP_BY_HOP_HEADERS = new Set([
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
    if (!HOP_BY_HOP_HEADERS.has(key.toLowerCase())) {
      result[key] = value;
    }
  }
  return result;
}

// -- Proxy --------------------------------------------------------------------

const upstreamBase = new URL(LLAMA_SERVER_URL);

function proxyToUpstream(req, res) {
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
      res.on('close', () => {
        proxyRes.destroy();
        proxyReq.destroy();
      });
    }
  );

  req.pipe(proxyReq);

  proxyReq.on('error', (error) => {
    log('warn', 'proxy_upstream_error', { error: error.message, path: req.url });
    if (!res.headersSent) {
      res.writeHead(502);
      res.end('Bad Gateway\n');
    }
  });
}

// -- HTTP server --------------------------------------------------------------

const INFERENCE_PATHS = new Set(['/v1/chat/completions', '/v1/completions']);

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
      res.end(JSON.stringify({ active: containerState === ContainerState.RUNNING, containerState }));
      return;
    }

    if (req.method === 'POST' && INFERENCE_PATHS.has(requestPath)) {
      recordActivity();
    }

    if (SCALE_TO_ZERO) {
      if (containerState === ContainerState.STOPPED) {
        pendingRequests.push({ req, res });
        startContainer().catch(console.error);
        return;
      }
      if (containerState === ContainerState.STARTING || containerState === ContainerState.STOPPING) {
        pendingRequests.push({ req, res });
        return;
      }
    }

    proxyToUpstream(req, res);
  });

  server.listen(PORT, '0.0.0.0', async () => {
    log('info', 'server_started', {
      container: LLAMA_CPP_CONTAINER,
      idleSeconds: LLAMA_CPP_SLEEP_IDLE_SECONDS,
      listen: `0.0.0.0:${PORT}`,
      logLevel: LOG_LEVEL,
      scaleToZero: SCALE_TO_ZERO,
      timeoutSeconds: UPSTREAM_TIMEOUT_SECONDS,
      upstream: LLAMA_SERVER_URL,
    });
    await syncContainerState();
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
