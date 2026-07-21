import { createServer, request as httpRequest } from 'node:http';
import { isImageInferencePath } from './models.js';

const SD_SERVER_URL = (process.env.SD_SERVER_URL ?? 'http://stable-diffusion-cpp:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '8000', 10);
// Image generation streams no bytes for tens of seconds, so the proxied socket
// must tolerate a long period of upstream silence. Keep this well above the
// worst-case single-image latency (nginx uses the same 900s ceiling).
const PROXY_TIMEOUT_SECONDS = Number.parseFloat(process.env.PROXY_TIMEOUT_SECONDS ?? '900');
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

function log(level, message, fields) {
  if (!shouldLog(level)) {
    return;
  }

  const base = `[sd-manager] ${level.toUpperCase()} ${message}`;
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

function getIdleTimeoutSeconds() {
  return Number.parseFloat(process.env.SD_CPP_SLEEP_IDLE_SECONDS ?? '0');
}

function isIdleModeEnabled() {
  return getIdleTimeoutSeconds() > 0;
}

export function recordActivity() {
  const wasActive = isActive();
  lastActivityAt = Date.now();
  if (!wasActive) {
    log('info', 'image_activity_detected');
  }
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
}

export function beginTrackedRequest() {
  activeProxyRequests += 1;
}

export function endTrackedRequest() {
  activeProxyRequests = Math.max(0, activeProxyRequests - 1);
}

export function getActiveProxyRequests() {
  return activeProxyRequests;
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

const upstreamBase = new URL(SD_SERVER_URL);

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
      headers: {
        ...stripHopByHopHeaders(req.headers),
        host: upstreamBase.host,
      },
      hostname: upstreamBase.hostname,
      method: req.method,
      path: req.url,
      port: Number(upstreamBase.port) || 80,
      timeout: PROXY_TIMEOUT_SECONDS * 1000,
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

  proxyReq.on('timeout', () => {
    log('warn', 'proxy_upstream_timeout', { path: req.url });
    proxyReq.destroy(new Error('upstream timeout'));
  });

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

export function startServer() {
  const server = createServer((req, res) => {
    const [requestPath] = (req.url ?? '/').split('?');

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
          lastActivityAt,
        })
      );
      return;
    }

    const isImageRequest = req.method === 'POST' && isImageInferencePath(requestPath);

    if (isImageRequest) {
      recordActivity();
    }

    proxyToUpstream(req, res, { trackRequest: isImageRequest });
  });

  server.listen(PORT, '0.0.0.0', () => {
    log('info', 'server_started', {
      idleSeconds: getIdleTimeoutSeconds(),
      listen: `0.0.0.0:${PORT}`,
      logLevel: LOG_LEVEL,
      proxyTimeoutSeconds: PROXY_TIMEOUT_SECONDS,
      upstream: SD_SERVER_URL,
    });
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
