import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildMetricsPayload,
  expandModelNames,
  exporterStatusLines,
  injectModelLabel,
  loadModelsConfigFromText,
  mergeMetricsForModels,
} from './llama-metrics-exporter.js';

test('loadModelsConfigFromText parses models array', () => {
  const config = loadModelsConfigFromText(`{"version":"1","models":[{"name":"panther-minor","thinking":true}]}`);
  assert.equal(config.models.length, 1);
  assert.equal(config.models[0].name, 'panther-minor');
});

test('expandModelNames adds thinking variants from config', () => {
  const names = expandModelNames([
    { name: 'panther-minor', thinking: true },
    { name: 'panther-blazer', thinking: true },
    { name: 'panther-coder', thinking: false },
    { name: 'panther-coder-next', thinking: false },
  ]);

  assert.deepEqual(names, [
    'panther-minor',
    'panther-minor-thinking',
    'panther-blazer',
    'panther-blazer-thinking',
    'panther-coder',
    'panther-coder-next',
  ]);
});

test('injectModelLabel adds label for unlabeled series', () => {
  const line = 'llamacpp_tokens_predicted_total 123';
  assert.equal(injectModelLabel(line, 'panther-minor'), 'llamacpp_tokens_predicted_total{model="panther-minor"} 123');
});

test('injectModelLabel appends label to existing labels', () => {
  const line = 'llamacpp_tokens_predicted_total{instance="llama-cpp:8000"} 123';
  assert.equal(
    injectModelLabel(line, 'panther-minor'),
    'llamacpp_tokens_predicted_total{instance="llama-cpp:8000",model="panther-minor"} 123',
  );
});

test('mergeMetricsForModels deduplicates HELP/TYPE headers and labels samples', () => {
  const sample = `# HELP llamacpp_tokens_predicted_total Total predicted tokens
# TYPE llamacpp_tokens_predicted_total counter
llamacpp_tokens_predicted_total 100
`;

  const merged = mergeMetricsForModels({
    'panther-minor': sample,
    'panther-coder': sample.replace('100', '200'),
  }).join('\n');

  assert.equal((merged.match(/# HELP llamacpp_tokens_predicted_total/g) ?? []).length, 1);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="panther-minor"} 100/);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="panther-coder"} 200/);
});

test('exporterStatusLines reports configured and successful model counts', () => {
  const lines = exporterStatusLines(['panther-minor', 'panther-minor-thinking'], {
    'panther-minor': { ok: true },
    'panther-minor-thinking': { ok: false },
  }).join('\n');

  assert.match(lines, /panther_llama_metrics_exporter_configured_models 2/);
  assert.match(lines, /panther_llama_metrics_exporter_successful_models 1/);
  assert.match(lines, /panther_llama_metrics_exporter_model_up\{model="panther-minor"} 1/);
  assert.match(lines, /panther_llama_metrics_exporter_model_up\{model="panther-minor-thinking"} 0/);
});

test('buildMetricsPayload fetches router metrics for every configured model', async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(url.toString());

    const model = new URL(url).searchParams.get('model');
    return new Response(
      `# HELP llamacpp_tokens_predicted_total Total predicted tokens\n` +
        `# TYPE llamacpp_tokens_predicted_total counter\n` +
        `llamacpp_tokens_predicted_total ${model === 'panther-minor' ? 100 : 200}\n`,
      { status: 200 },
    );
  };

  const payload = await buildMetricsPayload(fetchImpl, ['panther-minor', 'panther-minor-thinking']);

  assert.deepEqual(calls, [
    'http://llama-cpp:8000/metrics?model=panther-minor',
    'http://llama-cpp:8000/metrics?model=panther-minor-thinking',
  ]);
  assert.match(payload, /panther_llama_metrics_exporter_successful_models 2/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="panther-minor"} 100/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="panther-minor-thinking"} 200/);
});

test('buildMetricsPayload tolerates per-model failures and exports model_up states', async () => {
  const fetchImpl = async (url) => {
    const model = new URL(url).searchParams.get('model');
    if (model === 'panther-coder') {
      return new Response('bad request', { status: 400, statusText: 'Bad Request' });
    }

    return new Response(
      '# HELP llamacpp_tokens_predicted_total Total predicted tokens\n' +
        '# TYPE llamacpp_tokens_predicted_total counter\n' +
        'llamacpp_tokens_predicted_total 321\n',
      { status: 200 },
    );
  };

  const payload = await buildMetricsPayload(fetchImpl, ['panther-minor', 'panther-coder']);

  assert.match(payload, /panther_llama_metrics_exporter_successful_models 1/);
  assert.match(payload, /panther_llama_metrics_exporter_model_up\{model="panther-minor"} 1/);
  assert.match(payload, /panther_llama_metrics_exporter_model_up\{model="panther-coder"} 0/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="panther-minor"} 321/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total\{model="panther-coder"}/);
});
