#!/usr/bin/env node

import { createServer } from 'node:http';

const CACHE_TTL_SECONDS = Number.parseFloat(process.env.CACHE_TTL_SECONDS ?? '5');
const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const PORT = 9091;
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');

const METRIC_LINE_RE = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*})?(\s+.+)$/;
const HELP_TYPE_RE = /^#\s+(HELP|TYPE)\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\b/;

const cache = {
  timestampMs: 0,
  payload: '',
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
  if (labels && labels.includes('model=')) {
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
    for (const rawLine of payload.split(/\r?\n/)) {
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
    '# HELP panther_llama_metrics_exporter_up Whether the llama metrics exporter completed its scrape cycle.',
    '# TYPE panther_llama_metrics_exporter_up gauge',
    'panther_llama_metrics_exporter_up 1',
    '# HELP panther_llama_metrics_exporter_discovered_models Number of models discovered via /v1/models.',
    '# TYPE panther_llama_metrics_exporter_discovered_models gauge',
    `panther_llama_metrics_exporter_discovered_models ${models.length}`,
    '# HELP panther_llama_metrics_exporter_loaded_models Number of models with status.value="loaded" from /v1/models.',
    '# TYPE panther_llama_metrics_exporter_loaded_models gauge',
    `panther_llama_metrics_exporter_loaded_models ${loadedCount}`,
    '# HELP panther_llama_metrics_exporter_metrics_scrape_up Whether scraping /metrics for the selected loaded model succeeded.',
    '# TYPE panther_llama_metrics_exporter_metrics_scrape_up gauge',
    `panther_llama_metrics_exporter_metrics_scrape_up ${metricsScrapeOk ? 1 : 0}`,
    '# HELP panther_llama_metrics_exporter_model_loaded Whether a model is currently reported as loaded by /v1/models.',
    '# TYPE panther_llama_metrics_exporter_model_loaded gauge',
    '# HELP panther_llama_metrics_exporter_model_up Whether /metrics was scraped for a model in this cycle.',
    '# TYPE panther_llama_metrics_exporter_model_up gauge',
  ];

  for (const model of models) {
    const isLoaded = model.status === 'loaded';
    lines.push(
      `panther_llama_metrics_exporter_model_loaded{model="${escapeLabelValue(model.id)}"} ${isLoaded ? 1 : 0}`,
    );
    lines.push(
      `panther_llama_metrics_exporter_model_up{model="${escapeLabelValue(model.id)}"} ${
        metricsScrapeOk && loadedModelId === model.id ? 1 : 0
      }`,
    );
  }

  return lines;
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

export async function fetchModelsList(fetchImpl = fetch) {
  const payload = await fetchJson('/v1/models', fetchImpl);
  return normalizeModelsPayload(payload);
}

export async function fetchMetricsText(model, fetchImpl = fetch) {
  const url = new URL(`${LLAMA_SERVER_URL}/metrics`);
  url.searchParams.set('model', model);

  const response = await fetchImpl(url, {
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
  });

  if (!response.ok) {
    const error = new Error(`upstream metrics request failed for ${model}: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
  }

  return response.text();
}

export async function buildMetricsPayload(fetchImpl = fetch) {
  const models = await fetchModelsList(fetchImpl);
  const loadedModel = pickLoadedModel(models);
  const modelToMetrics = {};
  let metricsScrapeOk = false;

  if (loadedModel) {
    try {
      modelToMetrics[loadedModel.id] = await fetchMetricsText(loadedModel.id, fetchImpl);
      metricsScrapeOk = true;
    } catch {
      metricsScrapeOk = false;
    }
  }

  const lines = [
    ...exporterStatusLines(models, loadedModel?.id ?? '', metricsScrapeOk),
    ...mergeMetricsForModels(modelToMetrics),
    '',
  ];

  return lines.join('\n');
}

function staleSuffix() {
  return [
    '# HELP panther_llama_metrics_exporter_stale Whether cached data is being served after a scrape error.',
    '# TYPE panther_llama_metrics_exporter_stale gauge',
    'panther_llama_metrics_exporter_stale 1',
    '',
  ].join('\n');
}

export function startServer() {
  const server = createServer(async (req, res) => {
    const path = new URL(req.url ?? '/', 'http://localhost').pathname;

    if (path === '/healthz') {
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
    if (cache.payload && nowMs - cache.timestampMs < CACHE_TTL_SECONDS * 1000) {
      res.writeHead(200, {
        'content-type': 'text/plain; version=0.0.4; charset=utf-8',
      });
      res.end(cache.payload);
      return;
    }

    try {
      const payload = await buildMetricsPayload();
      cache.payload = payload;
      cache.timestampMs = nowMs;
      res.writeHead(200, {
        'content-type': 'text/plain; version=0.0.4; charset=utf-8',
      });
      res.end(payload);
    } catch (error) {
      if (cache.payload) {
        const payload = `${cache.payload}${staleSuffix()}`;
        res.writeHead(200, {
          'content-type': 'text/plain; version=0.0.4; charset=utf-8',
        });
        res.end(payload);
        return;
      }

      const payload = [
        '# HELP panther_llama_metrics_exporter_up Whether the llama metrics exporter completed its scrape cycle.',
        '# TYPE panther_llama_metrics_exporter_up gauge',
        'panther_llama_metrics_exporter_up 0',
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
    console.log(
      `[llama-metrics-exporter] listening on 0.0.0.0:${PORT}, ` +
        `upstream=${LLAMA_SERVER_URL}, cache_ttl=${CACHE_TTL_SECONDS}s`,
    );
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
