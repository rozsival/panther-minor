import test from 'node:test';
import assert from 'node:assert/strict';

import {
  extractLoadedModels,
  extractLoadedModelTargets,
  injectModelLabel,
  loadPresetAliasesFromText,
  metricsEntriesByLabel,
  mergeMetricsForModels,
} from './llama-metrics-exporter.js';

test('extractLoadedModels prefers model_alias', () => {
  const payload = {
    slots: [
      {
        id: 0,
        model: '/models/.huggingface/panther-minor.gguf',
        model_alias: 'panther-minor-thinking',
        loaded: true,
      },
    ],
  };

  const models = extractLoadedModels(payload);
  assert.deepEqual(models, ['panther-minor-thinking']);
});

test('extractLoadedModels resolves alias from preset mapping', () => {
  const preset = `
[*]
[panther-minor]
model = /models/.huggingface/panther-minor.gguf
[panther-coder]
model = /models/.huggingface/panther-coder.gguf
`.trim();

  const { aliasesByModelPath, knownAliases } = loadPresetAliasesFromText(preset);
  const payload = {
    slots: [
      {
        id: 0,
        model: '/models/.huggingface/panther-coder.gguf',
        loaded: true,
      },
    ],
  };

  const models = extractLoadedModels(payload, aliasesByModelPath, knownAliases);
  assert.deepEqual(models, ['panther-coder']);
});

test('extractLoadedModelTargets keeps raw upstream model and friendly label separate', () => {
  const preset = `
[*]
[panther-coder]
model = /models/.huggingface/panther-coder.gguf
`.trim();

  const { aliasesByModelPath, knownAliases } = loadPresetAliasesFromText(preset);
  const payload = {
    slots: [
      {
        id: 0,
        model: '/models/.huggingface/panther-coder.gguf',
        loaded: true,
      },
    ],
  };

  const targets = extractLoadedModelTargets(payload, aliasesByModelPath, knownAliases);
  assert.deepEqual(targets, [
    {
      upstreamModel: '/models/.huggingface/panther-coder.gguf',
      labelModel: 'panther-coder',
    },
  ]);
});

test('metricsEntriesByLabel remaps upstream metrics to friendly labels', () => {
  const entries = metricsEntriesByLabel(
    [
      {
        upstreamModel: '/models/.huggingface/panther-minor.gguf',
        labelModel: 'panther-minor',
      },
    ],
    {
      '/models/.huggingface/panther-minor.gguf': 'llamacpp_tokens_predicted_total 123\n',
    },
  );

  assert.deepEqual(entries, {
    'panther-minor': 'llamacpp_tokens_predicted_total 123\n',
  });
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

test('mergeMetricsForModels deduplicates HELP/TYPE headers', () => {
  const sample = `# HELP llamacpp_tokens_predicted_total Total predicted tokens
# TYPE llamacpp_tokens_predicted_total counter
llamacpp_tokens_predicted_total 100
`;

  const merged = mergeMetricsForModels({
    'panther-minor': sample,
    'panther-coder': sample.replace('100', '200'),
  });

  assert.equal((merged.match(/# HELP llamacpp_tokens_predicted_total/g) ?? []).length, 1);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="panther-minor"} 100/);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="panther-coder"} 200/);
});
