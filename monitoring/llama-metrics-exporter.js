#!/usr/bin/env node

import { createServer } from 'node:http';
import { existsSync, readFileSync } from 'node:fs';

const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const PORT = Number.parseInt(process.env.PORT ?? '9101', 10);
const CACHE_TTL_SECONDS = Number.parseFloat(process.env.CACHE_TTL_SECONDS ?? '5');
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');
const LLAMA_MODELS_CONFIG_FILE = '/app/config.json';

const METRIC_LINE_RE = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*})?(\s+.+)$/;
const HELP_TYPE_RE = /^#\s+(HELP|TYPE)\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\b/;

const cache = {
  timestampMs: 0,
  payload: '',
};

export function loadModelsConfigFromText(text) {
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.models)) {
    throw new Error('models config must contain a models array');
  }
  return parsed;
}

export function expandModelNames(models) {
  const names = [];
  const seen = new Set();

  for (const model of models) {
    const baseName = typeof model?.name === 'string' ? model.name.trim() : '';
    if (!baseName) {
      continue;
    }

    for (const name of [baseName, model.thinking === true ? `${baseName}-thinking` : '']) {
      if (!name || seen.has(name)) {
        continue;
      }
      seen.add(name);
      names.push(name);
    }
  }

  return names;
}

export function loadModelNamesFromFile(filePath = LLAMA_MODELS_CONFIG_FILE) {
  if (!existsSync(filePath)) {
    throw new Error(`models config file not found: ${filePath}`);
  }

  const text = readFileSync(filePath, 'utf8');
  return expandModelNames(loadModelsConfigFromText(text).models);
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

export function exporterStatusLines(modelNames, resultsByModel) {
  const successfulModels = modelNames.filter((model) => resultsByModel[model]?.ok).length;
  const lines = [
    '# HELP panther_llama_metrics_exporter_up Whether the llama metrics exporter completed its scrape cycle.',
    '# TYPE panther_llama_metrics_exporter_up gauge',
    'panther_llama_metrics_exporter_up 1',
    '# HELP panther_llama_metrics_exporter_configured_models Number of configured router models.',
    '# TYPE panther_llama_metrics_exporter_configured_models gauge',
    `panther_llama_metrics_exporter_configured_models ${modelNames.length}`,
    '# HELP panther_llama_metrics_exporter_successful_models Number of models whose /metrics scrape succeeded.',
    '# TYPE panther_llama_metrics_exporter_successful_models gauge',
    `panther_llama_metrics_exporter_successful_models ${successfulModels}`,
    '# HELP panther_llama_metrics_exporter_model_up Whether the /metrics scrape succeeded for a model.',
    '# TYPE panther_llama_metrics_exporter_model_up gauge',
  ];

  for (const model of modelNames) {
    lines.push(
      `panther_llama_metrics_exporter_model_up{model="${escapeLabelValue(model)}"} ${resultsByModel[model]?.ok ? 1 : 0}`,
    );
  }

  return lines;
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

export async function buildMetricsPayload(fetchImpl = fetch, modelNames = loadModelNamesFromFile()) {
  const resultsByModel = {};
  const modelToMetrics = {};

  for (const model of modelNames) {
    try {
      modelToMetrics[model] = await fetchMetricsText(model, fetchImpl);
      resultsByModel[model] = { ok: true };
    } catch (error) {
      resultsByModel[model] = { ok: false, error };
    }
  }

  const lines = [...exporterStatusLines(modelNames, resultsByModel), ...mergeMetricsForModels(modelToMetrics), ''];

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
        `upstream=${LLAMA_SERVER_URL}, config=${LLAMA_MODELS_CONFIG_FILE}, cache_ttl=${CACHE_TTL_SECONDS}s`,
    );
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
