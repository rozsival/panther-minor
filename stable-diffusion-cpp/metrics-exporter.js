import { createServer } from 'node:http';
import { normalizeModelsPayload } from './models.js';

const CACHE_TTL_SECONDS = Number.parseFloat(process.env.CACHE_TTL_SECONDS ?? '5');
const SD_SERVER_URL = (process.env.SD_SERVER_URL ?? 'http://stable-diffusion-cpp:8000').replace(/\/$/, '');
const MANAGER_URL = (process.env.MANAGER_URL ?? 'http://sd-manager:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '9090', 10);
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

function log(level, message, fields) {
  if (!shouldLog(level)) {
    return;
  }

  const base = `[sd-metrics-exporter] ${level.toUpperCase()} ${message}`;
  if (!fields || Object.keys(fields).length === 0) {
    console.log(base);
    return;
  }

  const context = Object.entries(fields)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  console.log(`${base} ${context}`);
}

export function escapeLabelValue(value) {
  return value.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll('"', '\\"');
}

export async function queryManagerStatus(fetchImpl = fetch) {
  try {
    const response = await fetchImpl(`${MANAGER_URL}/status`, {
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
    });
    if (!response.ok) {
      log('warn', 'manager_status_request_failed', { status: response.status });
      return { active: true, activeProxyRequests: 0, lastActivityAt: 0, reachable: false };
    }
    const data = await response.json();
    return {
      active: data.active !== false,
      activeProxyRequests: Number.isFinite(data.activeProxyRequests) ? data.activeProxyRequests : 0,
      lastActivityAt: Number.isFinite(data.lastActivityAt) ? data.lastActivityAt : 0,
      reachable: true,
    };
  } catch (error) {
    log('warn', 'manager_status_unavailable', { error: error.message ?? String(error) });
    return { active: true, activeProxyRequests: 0, lastActivityAt: 0, reachable: false };
  }
}

export async function fetchModelsList(fetchImpl = fetch) {
  try {
    const response = await fetchImpl(`${SD_SERVER_URL}/v1/models`, {
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
    });
    if (!response.ok) {
      log('warn', 'models_request_failed', { status: response.status });
      return { models: [], reachable: false };
    }
    const models = normalizeModelsPayload(await response.json());
    return { models, reachable: true };
  } catch (error) {
    log('warn', 'models_unavailable', { error: error.message ?? String(error) });
    return { models: [], reachable: false };
  }
}

export function buildMetricsLines(managerStatus, modelsResult) {
  const isIdle = managerStatus.reachable && !managerStatus.active;
  const lastActivitySeconds = managerStatus.lastActivityAt > 0 ? managerStatus.lastActivityAt / 1000 : 0;
  const lines = [
    '# HELP sd_metrics_exporter_up Whether the stable-diffusion metrics exporter completed its scrape cycle.',
    '# TYPE sd_metrics_exporter_up gauge',
    'sd_metrics_exporter_up 1',
    '# HELP sd_metrics_exporter_server_up Whether the sd-server upstream answered the models request.',
    '# TYPE sd_metrics_exporter_server_up gauge',
    `sd_metrics_exporter_server_up ${modelsResult.reachable ? 1 : 0}`,
    '# HELP sd_metrics_exporter_manager_up Whether the sd-manager answered the status request.',
    '# TYPE sd_metrics_exporter_manager_up gauge',
    `sd_metrics_exporter_manager_up ${managerStatus.reachable ? 1 : 0}`,
    '# HELP sd_metrics_exporter_idle Whether sd-server is currently idle (no recent image activity).',
    '# TYPE sd_metrics_exporter_idle gauge',
    `sd_metrics_exporter_idle ${isIdle ? 1 : 0}`,
    '# HELP sd_metrics_exporter_active_requests Number of image requests currently proxied in flight.',
    '# TYPE sd_metrics_exporter_active_requests gauge',
    `sd_metrics_exporter_active_requests ${managerStatus.activeProxyRequests}`,
    '# HELP sd_metrics_exporter_last_activity_timestamp_seconds Unix time of the last recorded image activity.',
    '# TYPE sd_metrics_exporter_last_activity_timestamp_seconds gauge',
    `sd_metrics_exporter_last_activity_timestamp_seconds ${lastActivitySeconds}`,
    '# HELP sd_metrics_exporter_discovered_models Number of models advertised by sd-server /v1/models.',
    '# TYPE sd_metrics_exporter_discovered_models gauge',
    `sd_metrics_exporter_discovered_models ${modelsResult.models.length}`,
    '# HELP sd_metrics_exporter_model_available Whether a model is advertised by sd-server /v1/models.',
    '# TYPE sd_metrics_exporter_model_available gauge',
  ];

  for (const model of modelsResult.models) {
    lines.push(`sd_metrics_exporter_model_available{model="${escapeLabelValue(model.id)}"} 1`);
  }

  return lines;
}

export async function buildMetricsPayload(fetchImpl = fetch) {
  const managerStatus = await queryManagerStatus(fetchImpl);
  const modelsResult = await fetchModelsList(fetchImpl);
  log('info', 'scrape_cycle_done', {
    active: managerStatus.active,
    discoveredModels: modelsResult.models.length,
    inFlight: managerStatus.activeProxyRequests,
  });
  return [...buildMetricsLines(managerStatus, modelsResult), ''].join('\n');
}

/** @type {{ payload: string | null, timestampMs: number }} */
const cache = {
  payload: null,
  timestampMs: 0,
};
let refreshInFlight = null;

export async function refreshMetricsCache(fetchImpl = fetch) {
  if (refreshInFlight) {
    return refreshInFlight;
  }

  refreshInFlight = (async () => {
    const payload = await buildMetricsPayload(fetchImpl);
    cache.payload = payload;
    cache.timestampMs = Date.now();
    return payload;
  })();

  try {
    return await refreshInFlight;
  } finally {
    refreshInFlight = null;
  }
}

function startBackgroundRefresh() {
  const refreshIntervalMs = Math.max(1000, CACHE_TTL_SECONDS * 1000);
  const timer = setInterval(() => {
    refreshMetricsCache().catch((error) => {
      log('warn', 'background_refresh_failed', { error: error?.message ?? String(error) });
    });
  }, refreshIntervalMs);

  timer.unref?.();
  return timer;
}

export function startServer() {
  const backgroundRefreshTimer = startBackgroundRefresh();
  const server = createServer(async (req, res) => {
    const path = new URL(req.url ?? '/', 'http://localhost').pathname;

    if (path === '/health') {
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('ok\n');
      return;
    }

    if (path !== '/metrics') {
      res.writeHead(404);
      res.end();
      return;
    }

    const nowMs = Date.now();
    if (typeof cache.payload === 'string' && nowMs - cache.timestampMs < CACHE_TTL_SECONDS * 1000) {
      res.writeHead(200, { 'content-type': 'text/plain; version=0.0.4; charset=utf-8' });
      res.end(cache.payload);
      return;
    }

    try {
      const payload = await refreshMetricsCache();
      res.writeHead(200, { 'content-type': 'text/plain; version=0.0.4; charset=utf-8' });
      res.end(payload);
    } catch (error) {
      log('error', 'scrape_cycle_failed', { error: error?.message ?? String(error) });
      const payload = [
        '# HELP sd_metrics_exporter_up Whether the stable-diffusion metrics exporter completed its scrape cycle.',
        '# TYPE sd_metrics_exporter_up gauge',
        'sd_metrics_exporter_up 0',
        '',
      ].join('\n');
      res.writeHead(503, { 'content-type': 'text/plain; version=0.0.4; charset=utf-8' });
      res.end(payload);
    }
  });

  server.on('close', () => {
    clearInterval(backgroundRefreshTimer);
  });

  server.listen(PORT, '0.0.0.0', () => {
    log('info', 'server_started', {
      cacheTtlSeconds: CACHE_TTL_SECONDS,
      listen: `0.0.0.0:${PORT}`,
      logLevel: LOG_LEVEL,
      managerUrl: MANAGER_URL,
      timeoutSeconds: UPSTREAM_TIMEOUT_SECONDS,
      upstream: SD_SERVER_URL,
    });
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
