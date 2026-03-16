#!/usr/bin/env node

import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { basename, extname } from 'node:path';

const LLAMA_SERVER_URL = (process.env.LLAMA_SERVER_URL ?? 'http://llama-cpp:8000').replace(/\/$/, '');
const EXPORTER_PORT = Number.parseInt(process.env.EXPORTER_PORT ?? '9101', 10);
const CACHE_TTL_SECONDS = Number.parseFloat(process.env.CACHE_TTL_SECONDS ?? '5');
const UPSTREAM_TIMEOUT_SECONDS = Number.parseFloat(process.env.UPSTREAM_TIMEOUT_SECONDS ?? '4');
const LLAMA_PRESET_FILE = process.env.LLAMA_PRESET_FILE ?? '/models/preset.ini';

const MODEL_KEYS = ['model_alias', 'model_id', 'alias', 'model_name', 'model', 'model_path'];
const METRIC_LINE_RE = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*})?(\s+.+)$/;
const HELP_TYPE_RE = /^#\s+(HELP|TYPE)\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\b/;
const PATH_LIKE_RE = /[\\/]|\.gguf$/i;

const cache = {
  timestampMs: 0,
  payload: '',
};

let lastSuccessfulSlotsModel = '';

export function loadPresetAliasesFromText(text) {
  const aliasesByModelPath = new Map();
  const knownAliases = new Set();

  let currentSection = '';
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }

    const sectionMatch = line.match(/^\[(.+)]$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1].trim();
      if (currentSection && currentSection !== '*') {
        knownAliases.add(currentSection);
      }
      continue;
    }

    if (!currentSection || currentSection === '*') {
      continue;
    }

    const kvMatch = line.match(/^([^=]+)=(.*)$/);
    if (!kvMatch) {
      continue;
    }

    const key = kvMatch[1].trim();
    const value = kvMatch[2].trim();
    if (key !== 'model' || !value) {
      continue;
    }

    const aliases = aliasesByModelPath.get(value) ?? [];
    aliases.push(currentSection);
    aliasesByModelPath.set(value, aliases);
  }

  return { aliasesByModelPath, knownAliases };
}

export function loadPresetAliasesFromFile(filePath) {
  if (!existsSync(filePath)) {
    return { aliasesByModelPath: new Map(), knownAliases: new Set() };
  }
  const text = readFileSync(filePath, 'utf8');
  return loadPresetAliasesFromText(text);
}

const { aliasesByModelPath: ALIASES_BY_MODEL_PATH, knownAliases: KNOWN_ALIASES } =
  loadPresetAliasesFromFile(LLAMA_PRESET_FILE);

export function iterSlotObjects(payload) {
  if (Array.isArray(payload)) {
    return payload.filter((item) => item && typeof item === 'object');
  }

  if (!payload || typeof payload !== 'object') {
    return [];
  }

  for (const key of ['slots', 'data', 'items', 'models']) {
    const value = payload[key];
    if (Array.isArray(value)) {
      return value.filter((item) => item && typeof item === 'object');
    }
  }

  return [payload];
}

export function modelCandidatesForSlot(slot) {
  const candidates = [];

  for (const key of MODEL_KEYS) {
    const value = slot[key];
    if (typeof value === 'string' && value.trim()) {
      candidates.push(value.trim());
    }
  }

  const params = slot.params;
  if (params && typeof params === 'object') {
    for (const key of ['model', 'model_alias']) {
      const value = params[key];
      if (typeof value === 'string' && value.trim()) {
        candidates.push(value.trim());
      }
    }
  }

  return candidates;
}

export function normalizeModelCandidate(
  candidate,
  aliasesByModelPath = ALIASES_BY_MODEL_PATH,
  knownAliases = KNOWN_ALIASES,
) {
  const normalized = [];

  const aliasesFromPath = aliasesByModelPath.get(candidate) ?? [];
  normalized.push(...aliasesFromPath);

  if (knownAliases.has(candidate)) {
    normalized.push(candidate);
  }

  const fileStem = basename(candidate, extname(candidate));
  if (knownAliases.has(fileStem)) {
    normalized.push(fileStem);
  }

  if (!PATH_LIKE_RE.test(candidate)) {
    normalized.push(candidate);
  }

  const deduped = [];
  const seen = new Set();
  for (const value of normalized) {
    if (!value || seen.has(value)) {
      continue;
    }
    seen.add(value);
    deduped.push(value);
  }

  return deduped;
}

export function extractLoadedModels(payload, aliasesByModelPath = ALIASES_BY_MODEL_PATH, knownAliases = KNOWN_ALIASES) {
  return extractLoadedModelTargets(payload, aliasesByModelPath, knownAliases).map(({ labelModel }) => labelModel);
}

export function extractLoadedModelTargets(
  payload,
  aliasesByModelPath = ALIASES_BY_MODEL_PATH,
  knownAliases = KNOWN_ALIASES,
) {
  const models = [];
  const seenUpstream = new Set();
  const seenLabels = new Set();

  for (const slot of iterSlotObjects(payload)) {
    const state = String(slot.state ?? '').toLowerCase();
    const isLoaded = slot.loaded;
    if (['empty', 'idle_unloaded', 'unloaded'].includes(state) || isLoaded === false) {
      continue;
    }

    const rawCandidates = [];
    for (const rawCandidate of modelCandidatesForSlot(slot)) {
      if (['none', 'null', '-'].includes(rawCandidate.toLowerCase())) {
        continue;
      }

      rawCandidates.push(rawCandidate);
    }

    if (rawCandidates.length === 0) {
      continue;
    }

    const upstreamModel = rawCandidates[0];
    if (seenUpstream.has(upstreamModel)) {
      continue;
    }

    const labelCandidates = [];
    for (const rawCandidate of rawCandidates) {
      const candidates = normalizeModelCandidate(rawCandidate, aliasesByModelPath, knownAliases);
      for (const model of candidates) {
        if (labelCandidates.includes(model)) {
          continue;
        }
        labelCandidates.push(model);
      }
    }

    if (!labelCandidates.includes(upstreamModel)) {
      labelCandidates.push(upstreamModel);
    }

    const labelModel = labelCandidates.find((candidate) => !seenLabels.has(candidate)) ?? labelCandidates[0];
    if (!labelModel) {
      continue;
    }

    seenUpstream.add(upstreamModel);
    seenLabels.add(labelModel);
    models.push({ upstreamModel, labelModel });
  }

  return models;
}

export function metricsEntriesByLabel(modelTargets, metricsByUpstreamModel) {
  const entries = {};

  for (const { upstreamModel, labelModel } of modelTargets) {
    const payload = metricsByUpstreamModel[upstreamModel];
    if (!payload || labelModel in entries) {
      continue;
    }

    entries[labelModel] = payload;
  }

  return entries;
}

export function listSlotsQueryModels(preferredModel = lastSuccessfulSlotsModel, knownAliases = KNOWN_ALIASES) {
  const models = [];
  const seen = new Set();

  for (const candidate of [preferredModel, ...knownAliases]) {
    if (typeof candidate !== 'string') {
      continue;
    }

    const model = candidate.trim();
    if (!model || seen.has(model)) {
      continue;
    }

    seen.add(model);
    models.push(model);
  }

  return models;
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
  const lines = [
    '# HELP panther_llama_metrics_exporter_up Whether the router-safe llama metrics exporter succeeded.',
    '# TYPE panther_llama_metrics_exporter_up gauge',
    'panther_llama_metrics_exporter_up 1',
    '# HELP panther_llama_metrics_exporter_loaded_models Number of currently loaded models discovered via /slots.',
    '# TYPE panther_llama_metrics_exporter_loaded_models gauge',
    `panther_llama_metrics_exporter_loaded_models ${Object.keys(modelToMetrics).length}`,
  ];

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

  return `${lines.join('\n')}\n`;
}

function metricsForNoModels() {
  return [
    '# HELP panther_llama_metrics_exporter_up Whether the router-safe llama metrics exporter succeeded.',
    '# TYPE panther_llama_metrics_exporter_up gauge',
    'panther_llama_metrics_exporter_up 1',
    '# HELP panther_llama_metrics_exporter_loaded_models Number of currently loaded models discovered via /slots.',
    '# TYPE panther_llama_metrics_exporter_loaded_models gauge',
    'panther_llama_metrics_exporter_loaded_models 0',
    '',
  ].join('\n');
}

async function fetchJsonWithQuery(pathname, query = undefined) {
  const url = new URL(`${LLAMA_SERVER_URL}${pathname}`);
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }
  }

  const response = await fetch(url, {
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

async function fetchText(pathname, query = undefined) {
  const url = new URL(`${LLAMA_SERVER_URL}${pathname}`);
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }
  }

  const response = await fetch(url, {
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_SECONDS * 1000),
  });
  if (!response.ok) {
    const error = new Error(`upstream text request failed: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
  }
  return response.text();
}

export async function discoverSlotsPayload(
  fetchJsonImpl = fetchJsonWithQuery,
  aliasesByModelPath = ALIASES_BY_MODEL_PATH,
  knownAliases = KNOWN_ALIASES,
) {
  try {
    const payload = await fetchJsonImpl('/slots');
    lastSuccessfulSlotsModel = '';
    return payload;
  } catch (error) {
    if (error?.status !== 400) {
      throw error;
    }
  }

  for (const model of listSlotsQueryModels(lastSuccessfulSlotsModel, knownAliases)) {
    try {
      const payload = await fetchJsonImpl('/slots', { model });
      if (extractLoadedModelTargets(payload, aliasesByModelPath, knownAliases).length > 0) {
        lastSuccessfulSlotsModel = model;
        return payload;
      }
    } catch (error) {
      if (error?.status === 400) {
        continue;
      }
      throw error;
    }
  }

  return { slots: [] };
}

export async function buildMetricsPayload() {
  const slotsPayload = await discoverSlotsPayload();
  const modelTargets = extractLoadedModelTargets(slotsPayload);

  if (modelTargets.length === 0) {
    return metricsForNoModels();
  }

  const metricsByUpstreamModel = {};
  for (const { upstreamModel } of modelTargets) {
    metricsByUpstreamModel[upstreamModel] = await fetchText('/metrics', { model: upstreamModel });
  }

  return mergeMetricsForModels(metricsEntriesByLabel(modelTargets, metricsByUpstreamModel));
}

function staleSuffix() {
  return [
    '# HELP panther_llama_metrics_exporter_stale Whether cached data is being served after an upstream error.',
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
        '# HELP panther_llama_metrics_exporter_up Whether the router-safe llama metrics exporter succeeded.',
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

  server.listen(EXPORTER_PORT, '0.0.0.0', () => {
    console.log(
      `[llama-metrics-exporter] listening on 0.0.0.0:${EXPORTER_PORT}, ` +
        `upstream=${LLAMA_SERVER_URL}, cache_ttl=${CACHE_TTL_SECONDS}s`,
    );
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer();
}
