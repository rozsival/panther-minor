import test from 'node:test';
import assert from 'node:assert/strict';

import {
  extractLoadedModels,
  injectModelLabel,
  loadPresetAliasesFromText,
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

test('injectModelLabel adds label for unlabeled series', () => {
  const line = 'llamacpp:tokens_predicted_total 123';
  assert.equal(injectModelLabel(line, 'panther-minor'), 'llamacpp:tokens_predicted_total{model="panther-minor"} 123');
});

test('injectModelLabel appends label to existing labels', () => {
  const line = 'llamacpp:tokens_predicted_total{instance="llama-cpp:8000"} 123';
  assert.equal(
    injectModelLabel(line, 'panther-minor'),
    'llamacpp:tokens_predicted_total{instance="llama-cpp:8000",model="panther-minor"} 123',
  );
});

test('mergeMetricsForModels deduplicates HELP/TYPE headers', () => {
  const sample = `# HELP llamacpp:tokens_predicted_total Total predicted tokens
# TYPE llamacpp:tokens_predicted_total counter
llamacpp:tokens_predicted_total 100
`;

  const merged = mergeMetricsForModels({
    'panther-minor': sample,
    'panther-coder': sample.replace('100', '200'),
  });

  assert.equal((merged.match(/# HELP llamacpp:tokens_predicted_total/g) ?? []).length, 1);
  assert.match(merged, /llamacpp:tokens_predicted_total\{model="panther-minor"} 100/);
  assert.match(merged, /llamacpp:tokens_predicted_total\{model="panther-coder"} 200/);
});
