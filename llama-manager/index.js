import { createServer, request as httpRequest } from 'node:http';

const LLAMA_CPP_SLEEP_IDLE_SECONDS = Number.parseFloat(process.env.LLAMA_CPP_SLEEP_IDLE_SECONDS ?? '0');
const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '8000', 10);
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');
const LOG_LEVEL = (process.env.LOG_LEVEL ?? 'info').toLowerCase();

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

let lastActivityAt = 0;

export function recordActivity() {
  const wasActive = isActive();
  lastActivityAt = Date.now();
  if (!wasActive) {
    log('info', 'inference_activity_detected');
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

// -- HTTP server --------------------------------------------------------------

const INFERENCE_PATHS = new Set(['/v1/chat/completions', '/v1/completions']);

export function startServer() {
  const upstreamBase = new URL(LLAMA_SERVER_URL);

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
      res.end(JSON.stringify({ active: isActive() }));
      return;
    }

    if (req.method === 'POST' && INFERENCE_PATHS.has(requestPath)) {
      recordActivity();
    }

    const proxyOptions = {
      hostname: upstreamBase.hostname,
      port: Number(upstreamBase.port) || 80,
      path: req.url,
      method: req.method,
      headers: { ...stripHopByHopHeaders(req.headers), host: upstreamBase.host },
      timeout: UPSTREAM_TIMEOUT_SECONDS * 1000,
    };

    const proxyReq = httpRequest(proxyOptions, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, stripHopByHopHeaders(proxyRes.headers));
      proxyRes.pipe(res);
      res.on('close', () => {
        proxyRes.destroy();
        proxyReq.destroy();
      });
    });

    req.pipe(proxyReq);

    proxyReq.on('error', (error) => {
      log('warn', 'proxy_upstream_error', { error: error.message, path: req.url });
      if (!res.headersSent) {
        res.writeHead(502);
        res.end('Bad Gateway\n');
      }
    });
  });

  server.listen(PORT, '0.0.0.0', () => {
    log('info', 'server_started', {
      idleSeconds: LLAMA_CPP_SLEEP_IDLE_SECONDS,
      listen: `0.0.0.0:${PORT}`,
      logLevel: LOG_LEVEL,
      timeoutSeconds: UPSTREAM_TIMEOUT_SECONDS,
      upstream: LLAMA_SERVER_URL,
    });
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
