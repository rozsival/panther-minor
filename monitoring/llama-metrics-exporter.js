#!/usr/bin/env node

import { createServer } from 'node:http';

const CACHE_TTL_SECONDS = Number.parseFloat(process.env.CACHE_TTL_SECONDS ?? '5');
const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '9101', 10);
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');
const LOG_LEVEL = (process.env.LOG_LEVEL ?? 'info').toLowerCase();

const LOG_PRIORITY = {
  debug: 3,
  error: 0,
  info: 2,
  warn: 1,
};

const METRICS_RAW_LINE_REGEX = /\r?\n/;

function shouldLog(level) {
  return (LOG_PRIORITY[level] ?? LOG_PRIORITY.info) <= (LOG_PRIORITY[LOG_LEVEL] ?? LOG_PRIORITY.info);
}

function log(level, message, fields = undefined) {
  if (!shouldLog(level)) {
    return;
  }

  const base = `[llama-metrics-exporter] ${level.toUpperCase()} ${message}`;
  if (!fields || Object.keys(fields).length === 0) {
    console.log(base);
    return;
  }

  const context = Object.entries(fields)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  console.log(`${base} ${context}`);
}

const METRIC_LINE_RE = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*})?(\s+.+)$/;
const HELP_TYPE_RE = /^#\s+(HELP|TYPE)\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\b/;

const cache = {
  payload: '',
  timestampMs: 0,
};

export function normalizeModelsPayload(payload) {
  const data = Array.isArray(payload?.data) ? payload.data : [];
  const models = [];
  const seen = new Set();

  for (const item of data) {
    const id = typeof item?.id === 'string' ? item.id.trim() : '';
    if (!id || seen.has(id)) {
      continue;
    }

    const statusValue = typeof item?.status?.value === 'string' ? item.status.value.trim().toLowerCase() : 'unknown';
    seen.add(id);
    models.push({ id, status: statusValue });
  }

  return models;
}

export function pickLoadedModel(models) {
  return models.find((model) => model.status === 'loaded') ?? null;
}

export function escapeLabelValue(value) {
  return value.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll('"', '\\"');
}

export function injectModelLabel(metricLine, model) {
  const match = metricLine.match(METRIC_LINE_RE);
  if (!match) {
    return metricLine;
  }

  const [, metricName, labels, suffix] = match;
  if (labels?.includes('model=')) {
    return metricLine;
  }

  const modelLabel = `model="${escapeLabelValue(model)}"`;
  if (labels) {
    return `${metricName}${labels.slice(0, -1)},${modelLabel}}${suffix}`;
  }
  return `${metricName}{${modelLabel}}${suffix}`;
}

export function mergeMetricsForModels(modelToMetrics) {
  const lines = [];
  const seenHeaders = new Set();
  const modelEntries = Object.entries(modelToMetrics).sort((a, b) => a[0].localeCompare(b[0]));

  for (const [model, payload] of modelEntries) {
    for (const rawLine of payload.split(METRICS_RAW_LINE_REGEX)) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }

      const headerMatch = line.match(HELP_TYPE_RE);
      if (headerMatch) {
        const headerKey = `${headerMatch[1]}:${headerMatch[2]}`;
        if (seenHeaders.has(headerKey)) {
          continue;
        }
        seenHeaders.add(headerKey);
        lines.push(line);
        continue;
      }

      if (line.startsWith('#')) {
        continue;
      }

      lines.push(injectModelLabel(line, model));
    }
  }

  return lines;
}

export function exporterStatusLines(models, loadedModelId, metricsScrapeOk) {
  const loadedCount = models.filter((model) => model.status === 'loaded').length;
  const lines = [
    '# HELP llama_metrics_exporter_up Whether the llama metrics exporter completed its scrape cycle.',
    '# TYPE llama_metrics_exporter_up gauge',
    'llama_metrics_exporter_up 1',
    '# HELP llama_metrics_exporter_discovered_models Number of models discovered via /v1/models.',
    '# TYPE llama_metrics_exporter_discovered_models gauge',
    `llama_metrics_exporter_discovered_models ${models.length}`,
    '# HELP llama_metrics_exporter_loaded_models Number of models with status.value="loaded" from /v1/models.',
    '# TYPE llama_metrics_exporter_loaded_models gauge',
    `llama_metrics_exporter_loaded_models ${loadedCount}`,
    '# HELP llama_metrics_exporter_metrics_scrape_up Whether scraping /metrics for the selected loaded model succeeded.',
    '# TYPE llama_metrics_exporter_metrics_scrape_up gauge',
    `llama_metrics_exporter_metrics_scrape_up ${metricsScrapeOk ? 1 : 0}`,
    '# HELP llama_metrics_exporter_model_loaded Whether a model is currently reported as loaded by /v1/models.',
    '# TYPE llama_metrics_exporter_model_loaded gauge',
    '# HELP llama_metrics_exporter_model_up Whether /metrics was scraped for a model in this cycle.',
    '# TYPE llama_metrics_exporter_model_up gauge',
  ];

  for (const model of models) {
    const isLoaded = model.status === 'loaded';
    lines.push(`llama_metrics_exporter_model_loaded{model="${escapeLabelValue(model.id)}"} ${isLoaded ? 1 : 0}`);
    lines.push(
      `llama_metrics_exporter_model_up{model="${escapeLabelValue(model.id)}"} ${
        metricsScrapeOk && loadedModelId === model.id ? 1 : 0
      }`
    );
  }

  return lines;
}

async function fetchJson(pathname, fetchImpl = fetch) {
  const url = new URL(`${LLAMA_SERVER_URL}${pathname}`);
  log('debug', 'upstream_json_request_start', { url: url.toString() });
  const response = await fetchImpl(url, {
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
  });

  if (!response.ok) {
    log('warn', 'upstream_json_request_failed', {
      status: response.status,
      statusText: response.statusText,
      url: url.toString(),
    });
    const error = new Error(`upstream json request failed: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
  }

  log('debug', 'upstream_json_request_ok', {
    status: response.status,
    url: url.toString(),
  });

  return response.json();
}

export async function fetchModelsList(fetchImpl = fetch) {
  const payload = await fetchJson('/v1/models', fetchImpl);
  const models = normalizeModelsPayload(payload);
  log('info', 'models_discovered', {
    count: models.length,
    loaded: models.filter((model) => model.status === 'loaded').map((model) => model.id),
  });
  return models;
}

export async function fetchMetricsText(model, fetchImpl = fetch) {
  const url = new URL(`${LLAMA_SERVER_URL}/metrics`);
  url.searchParams.set('model', model);
  log('info', 'model_metrics_request_start', { model, url: url.toString() });

  const response = await fetchImpl(url, {
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
  });

  if (!response.ok) {
    log('warn', 'model_metrics_request_failed', {
      model,
      status: response.status,
      statusText: response.statusText,
    });
    const error = new Error(`upstream metrics request failed for ${model}: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
  }

  log('info', 'model_metrics_request_ok', { model, status: response.status });

  const payload = await response.text();
  const metricNames = [];
  const seen = new Set();
  for (const rawLine of payload.split(METRICS_RAW_LINE_REGEX)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }

    const metricName = line.split('{', 1)[0].split(' ', 1)[0];
    if (!metricName || seen.has(metricName)) {
      continue;
    }
    seen.add(metricName);
    metricNames.push(metricName);
  }

  log('info', 'model_metrics_payload_received', {
    metricCount: metricNames.length,
    model,
    sampleMetrics: metricNames.slice(0, 10),
  });

  return payload;
}

export async function buildMetricsPayload(fetchImpl = fetch) {
  log('info', 'scrape_cycle_start');
  const models = await fetchModelsList(fetchImpl);
  const loadedModel = pickLoadedModel(models);
  const modelToMetrics = {};
  let metricsScrapeOk = false;

  if (loadedModel) {
    log('info', 'loaded_model_selected', { model: loadedModel.id });
    try {
      modelToMetrics[loadedModel.id] = await fetchMetricsText(loadedModel.id, fetchImpl);
      metricsScrapeOk = true;
    } catch {
      metricsScrapeOk = false;
    }
  } else {
    log('warn', 'no_loaded_model_reported');
  }

  const lines = [
    ...exporterStatusLines(models, loadedModel?.id ?? '', metricsScrapeOk),
    ...mergeMetricsForModels(modelToMetrics),
    '',
  ];

  log('info', 'scrape_cycle_done', {
    discoveredModels: models.length,
    loadedModel: loadedModel?.id ?? null,
    metricsScrapeOk,
  });

  return lines.join('\n');
}

function staleSuffix() {
  return [
    '# HELP llama_metrics_exporter_stale Whether cached data is being served after a scrape error.',
    '# TYPE llama_metrics_exporter_stale gauge',
    'llama_metrics_exporter_stale 1',
    '',
  ].join('\n');
}

export function startServer() {
  const server = createServer(async (req, res) => {
    const requestUrl = new URL(req.url ?? '/', 'http://localhost');
    const path = requestUrl.pathname;

    if (path === '/health') {
      log('debug', 'healthz_request');
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('ok\n');
      return;
    }

    if (path !== '/metrics') {
      res.writeHead(404);
      res.end();
      return;
    }

    log('info', 'metrics_request_received', {
      path,
      query: requestUrl.search,
    });

    const nowMs = Date.now();
    if (cache.payload && nowMs - cache.timestampMs < CACHE_TTL_SECONDS * 1000) {
      log('info', 'scrape_cache_hit', {
        ageMs: nowMs - cache.timestampMs,
      });
      res.writeHead(200, {
        'content-type': 'text/plain; version=0.0.4; charset=utf-8',
      });
      res.end(cache.payload);
      return;
    }

    try {
      log('debug', 'scrape_cache_miss');
      const payload = await buildMetricsPayload();
      cache.payload = payload;
      cache.timestampMs = nowMs;
      res.writeHead(200, {
        'content-type': 'text/plain; version=0.0.4; charset=utf-8',
      });
      res.end(payload);
    } catch (error) {
      log('error', 'scrape_cycle_failed', {
        error: error?.message ?? String(error),
      });
      if (cache.payload) {
        log('warn', 'serving_stale_payload');
        const payload = `${cache.payload}${staleSuffix()}`;
        res.writeHead(200, {
          'content-type': 'text/plain; version=0.0.4; charset=utf-8',
        });
        res.end(payload);
        return;
      }

      const payload = [
        '# HELP llama_metrics_exporter_up Whether the llama metrics exporter completed its scrape cycle.',
        '# TYPE llama_metrics_exporter_up gauge',
        'llama_metrics_exporter_up 0',
        `# upstream_error ${error?.name ?? 'Error'}: ${error?.message ?? String(error)}`,
        '',
      ].join('\n');
      res.writeHead(503, {
        'content-type': 'text/plain; version=0.0.4; charset=utf-8',
      });
      res.end(payload);
    }
  });

  server.listen(PORT, '0.0.0.0', () => {
    log('info', 'server_started', {
      cacheTtlSeconds: CACHE_TTL_SECONDS,
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
