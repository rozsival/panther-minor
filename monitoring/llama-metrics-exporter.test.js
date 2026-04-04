// biome-ignore-all lint/performance/useTopLevelRegex: We don't need hoisted regexes for tests.
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildIdlePayload,
  buildMetricsPayload,
  exporterStatusLines,
  injectModelLabel,
  mergeMetricsForModels,
  normalizeModelsPayload,
  pickLoadedModel,
  resetLastSuccessfulScrape,
  resetModelsCache,
} from './llama-metrics-exporter.js';

test('normalizeModelsPayload maps OpenAI models response', () => {
  const models = normalizeModelsPayload({
    data: [
      { id: 'panther-minor', status: { value: 'loaded' } },
      { id: 'panther-coder', status: { value: 'unloaded' } },
    ],
    object: 'list',
  });

  assert.deepEqual(models, [
    { id: 'panther-minor', status: 'loaded' },
    { id: 'panther-coder', status: 'unloaded' },
  ]);
});

test('normalizeModelsPayload excludes models with "embedding" in the id', () => {
  const models = normalizeModelsPayload({
    data: [
      { id: 'panther-minor', status: { value: 'loaded' } },
      { id: 'panther-embedding', status: { value: 'loaded' } },
      { id: 'text-embedding-3-small', status: { value: 'unloaded' } },
    ],
    object: 'list',
  });

  assert.deepEqual(models, [{ id: 'panther-minor', status: 'loaded' }]);
});

test('pickLoadedModel returns first loaded model', () => {
  const loaded = pickLoadedModel([
    { id: 'panther-coder', status: 'unloaded' },
    { id: 'panther-minor', status: 'loaded' },
    { id: 'panther-blazer', status: 'loaded' },
  ]);

  assert.deepEqual(loaded, { id: 'panther-minor', status: 'loaded' });
});

test('injectModelLabel adds label for unlabeled series', () => {
  const line = 'llamacpp_tokens_predicted_total 123';
  assert.equal(injectModelLabel(line, 'panther-minor'), 'llamacpp_tokens_predicted_total{model="panther-minor"} 123');
});

test('injectModelLabel appends label to existing labels', () => {
  const line = 'llamacpp_tokens_predicted_total{instance="llama-cpp:8000"} 123';
  assert.equal(
    injectModelLabel(line, 'panther-minor'),
    'llamacpp_tokens_predicted_total{instance="llama-cpp:8000",model="panther-minor"} 123'
  );
});

test('mergeMetricsForModels deduplicates HELP/TYPE headers and labels samples', () => {
  const sample = `# HELP llamacpp_tokens_predicted_total Total predicted tokens
# TYPE llamacpp_tokens_predicted_total counter
llamacpp_tokens_predicted_total 100
`;

  const merged = mergeMetricsForModels({
    'panther-coder': sample.replace('100', '200'),
    'panther-minor': sample,
  }).join('\n');

  assert.equal((merged.match(/# HELP llamacpp_tokens_predicted_total/g) ?? []).length, 1);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="panther-minor"} 100/);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="panther-coder"} 200/);
});

test('exporterStatusLines reports discovered and loaded states', () => {
  const lines = exporterStatusLines(
    [
      { id: 'panther-minor', status: 'loaded' },
      { id: 'panther-coder', status: 'unloaded' },
    ],
    new Set(['panther-minor'])
  ).join('\n');

  assert.match(lines, /llama_metrics_exporter_idle 0/);
  assert.match(lines, /llama_metrics_exporter_discovered_models 2/);
  assert.match(lines, /llama_metrics_exporter_loaded_models 1/);
  assert.match(lines, /llama_metrics_exporter_metrics_scrape_up 1/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="panther-minor"} 1/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="panther-coder"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="panther-minor"} 1/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="panther-coder"} 0/);
});

test('exporterStatusLines reports idle state with all models unloaded and no scrape', () => {
  const lines = exporterStatusLines(
    [
      { id: 'panther-minor', status: 'loaded' },
      { id: 'panther-coder', status: 'unloaded' },
    ],
    new Set(['panther-minor']),
    true
  ).join('\n');

  assert.match(lines, /llama_metrics_exporter_idle 1/);
  assert.match(lines, /llama_metrics_exporter_loaded_models 0/);
  assert.match(lines, /llama_metrics_exporter_metrics_scrape_up 0/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="panther-minor"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="panther-coder"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="panther-minor"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="panther-coder"} 0/);
});

test('recordActivity and buildIdlePayload serve stale model metrics', async () => {
  resetModelsCache();
  resetLastSuccessfulScrape();

  const fetchImpl = (url, _options) => {
    const pathname = new URL(url).pathname;
    if (pathname === '/v1/models') {
      return new Response(
        JSON.stringify({
          data: [{ id: 'panther-minor', status: { value: 'loaded' } }],
          object: 'list',
        }),
        { status: 200 }
      );
    }
    return new Response(
      '# HELP llamacpp_tokens_predicted_total Total predicted tokens\n' +
        '# TYPE llamacpp_tokens_predicted_total counter\n' +
        'llamacpp_tokens_predicted_total 42\n',
      { status: 200 }
    );
  };

  // Build a real payload first to populate lastSuccessfulScrape
  await buildMetricsPayload(fetchImpl);

  // Build idle payload — should serve stale model metrics
  const idlePayload = buildIdlePayload();

  assert.match(idlePayload, /llama_metrics_exporter_idle 1/);
  assert.match(idlePayload, /llama_metrics_exporter_metrics_scrape_up 0/);
  assert.match(idlePayload, /llama_metrics_exporter_model_loaded\{model="panther-minor"} 0/);
  // Stale model counter metrics are still present to prevent Grafana "No data"
  assert.match(idlePayload, /llamacpp_tokens_predicted_total\{model="panther-minor"} 42/);
});

test('buildIdlePayload with no prior scrape returns only status lines', () => {
  resetLastSuccessfulScrape();
  resetModelsCache();

  const payload = buildIdlePayload();
  assert.match(payload, /llama_metrics_exporter_up 1/);
  assert.match(payload, /llama_metrics_exporter_idle 1/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total/);
});

test('buildMetricsPayload scrapes metrics for all available models', async () => {
  resetModelsCache();
  resetLastSuccessfulScrape();
  const calls = [];
  const fetchImpl = (url, _options) => {
    calls.push(url.toString());

    const pathname = new URL(url).pathname;
    if (pathname === '/v1/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'panther-minor', status: { value: 'loaded' } },
            { id: 'panther-coder', status: { value: 'unloaded' } },
          ],
          object: 'list',
        }),
        { status: 200 }
      );
    }

    const model = new URL(url).searchParams.get('model');
    return new Response(
      '# HELP llamacpp_tokens_predicted_total Total predicted tokens\n' +
        '# TYPE llamacpp_tokens_predicted_total counter\n' +
        `llamacpp_tokens_predicted_total ${model === 'panther-minor' ? 100 : 200}\n`,
      { status: 200 }
    );
  };

  const payload = await buildMetricsPayload(fetchImpl);

  assert.equal(calls.length, 3);
  assert.ok(calls.includes('http://llama-cpp:8000/v1/models'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=panther-minor&autoload=false'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=panther-coder&autoload=false'));
  assert.match(payload, /llama_metrics_exporter_idle 0/);
  assert.match(payload, /llama_metrics_exporter_discovered_models 2/);
  assert.match(payload, /llama_metrics_exporter_loaded_models 1/);
  assert.match(payload, /llama_metrics_exporter_metrics_scrape_up 1/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="panther-minor"} 100/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="panther-coder"} 200/);
});

test('buildMetricsPayload attempts metrics scrape for all models even when none are loaded', async () => {
  resetModelsCache();
  resetLastSuccessfulScrape();
  const calls = [];
  const fetchImpl = (url, _options) => {
    calls.push(url.toString());
    const pathname = new URL(url).pathname;
    if (pathname === '/v1/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'panther-minor', status: { value: 'unloaded' } },
            { id: 'panther-coder', status: { value: 'unloaded' } },
          ],
          object: 'list',
        }),
        { status: 200 }
      );
    }

    return new Response('model not loaded', { status: 404 });
  };

  const payload = await buildMetricsPayload(fetchImpl);

  assert.equal(calls.length, 3);
  assert.ok(calls.includes('http://llama-cpp:8000/v1/models'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=panther-minor&autoload=false'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=panther-coder&autoload=false'));
  assert.match(payload, /llama_metrics_exporter_idle 0/);
  assert.match(payload, /llama_metrics_exporter_loaded_models 0/);
  assert.match(payload, /llama_metrics_exporter_metrics_scrape_up 0/);
  assert.match(payload, /llama_metrics_exporter_model_up\{model="panther-minor"} 0/);
  assert.match(payload, /llama_metrics_exporter_model_up\{model="panther-coder"} 0/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total\{/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total\{/);
});
