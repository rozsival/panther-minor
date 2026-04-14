// biome-ignore-all lint/performance/useTopLevelRegex: We don't need hoisted regexes for tests.
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildIdlePayload,
  buildMetricsPayload,
  exporterStatusLines,
  injectModelLabel,
  mergeMetricsForModels,
  pickLoadedModel,
  resetLastSuccessfulScrape,
} from './metrics-exporter.js';
import { normalizeModelsPayload } from './models.js';

test('normalizeModelsPayload maps OpenAI models response', () => {
  const models = normalizeModelsPayload({
    data: [
      { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
      { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: { value: 'unloaded' } },
    ],
    object: 'list',
  });

  assert.deepEqual(models, [
    { id: 'qwen35-35b-a3b-q8_0', status: 'loaded' },
    { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: 'unloaded' },
  ]);
});

test('normalizeModelsPayload excludes models with "embedding" in the id', () => {
  const models = normalizeModelsPayload({
    data: [
      { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
      { id: 'qwen3-embedding-0-6b-q8_0', status: { value: 'loaded' } },
      { id: 'text-embedding-3-small', status: { value: 'unloaded' } },
    ],
    object: 'list',
  });

  assert.deepEqual(models, [{ id: 'qwen35-35b-a3b-q8_0', status: 'loaded' }]);
});

test('pickLoadedModel returns first loaded model', () => {
  const loaded = pickLoadedModel([
    { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: 'unloaded' },
    { id: 'qwen35-35b-a3b-q8_0', status: 'loaded' },
    { id: 'panther-blazer', status: 'loaded' },
  ]);

  assert.deepEqual(loaded, { id: 'qwen35-35b-a3b-q8_0', status: 'loaded' });
});

test('injectModelLabel adds label for unlabeled series', () => {
  const line = 'llamacpp_tokens_predicted_total 123';
  assert.equal(
    injectModelLabel(line, 'qwen35-35b-a3b-q8_0'),
    'llamacpp_tokens_predicted_total{model="qwen35-35b-a3b-q8_0"} 123'
  );
});

test('injectModelLabel appends label to existing labels', () => {
  const line = 'llamacpp_tokens_predicted_total{instance="llama-cpp:8000"} 123';
  assert.equal(
    injectModelLabel(line, 'qwen35-35b-a3b-q8_0'),
    'llamacpp_tokens_predicted_total{instance="llama-cpp:8000",model="qwen35-35b-a3b-q8_0"} 123'
  );
});

test('mergeMetricsForModels deduplicates HELP/TYPE headers and labels samples', () => {
  const sample = `# HELP llamacpp_tokens_predicted_total Total predicted tokens
# TYPE llamacpp_tokens_predicted_total counter
llamacpp_tokens_predicted_total 100
`;

  const merged = mergeMetricsForModels({
    'qwen3-coder-30b-a3b-instruct-q8_0': sample.replace('100', '200'),
    'qwen35-35b-a3b-q8_0': sample,
  }).join('\n');

  assert.equal((merged.match(/# HELP llamacpp_tokens_predicted_total/g) ?? []).length, 1);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="qwen35-35b-a3b-q8_0"} 100/);
  assert.match(merged, /llamacpp_tokens_predicted_total\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 200/);
});

test('exporterStatusLines reports discovered and loaded states', () => {
  const lines = exporterStatusLines(
    [
      { id: 'qwen35-35b-a3b-q8_0', status: 'loaded' },
      { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: 'unloaded' },
    ],
    new Set(['qwen35-35b-a3b-q8_0'])
  ).join('\n');

  assert.match(lines, /llama_metrics_exporter_idle 0/);
  assert.match(lines, /llama_metrics_exporter_discovered_models 2/);
  assert.match(lines, /llama_metrics_exporter_loaded_models 1/);
  assert.match(lines, /llama_metrics_exporter_metrics_scrape_up 1/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="qwen35-35b-a3b-q8_0"} 1/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="qwen35-35b-a3b-q8_0"} 1/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 0/);
});

test('exporterStatusLines reports idle state with all models unloaded and no scrape', () => {
  const lines = exporterStatusLines(
    [
      { id: 'qwen35-35b-a3b-q8_0', status: 'loaded' },
      { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: 'unloaded' },
    ],
    new Set(['qwen35-35b-a3b-q8_0']),
    true
  ).join('\n');

  assert.match(lines, /llama_metrics_exporter_idle 1/);
  assert.match(lines, /llama_metrics_exporter_loaded_models 0/);
  assert.match(lines, /llama_metrics_exporter_metrics_scrape_up 0/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="qwen35-35b-a3b-q8_0"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_loaded\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="qwen35-35b-a3b-q8_0"} 0/);
  assert.match(lines, /llama_metrics_exporter_model_up\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 0/);
});

test('recordActivity and buildIdlePayload serve stale model metrics', async () => {
  resetLastSuccessfulScrape();

  const fetchImpl = (url, _options) => {
    const pathname = new URL(url).pathname;
    if (pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [{ id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } }],
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
  const idlePayload = await buildIdlePayload(fetchImpl);

  assert.match(idlePayload, /llama_metrics_exporter_idle 1/);
  assert.match(idlePayload, /llama_metrics_exporter_metrics_scrape_up 0/);
  assert.match(idlePayload, /llama_metrics_exporter_model_loaded\{model="qwen35-35b-a3b-q8_0"} 0/);
  // Stale model counter metrics are still present to prevent Grafana "No data"
  assert.match(idlePayload, /llamacpp_tokens_predicted_total\{model="qwen35-35b-a3b-q8_0"} 42/);
});

test('buildIdlePayload with no prior scrape returns only status lines', async () => {
  resetLastSuccessfulScrape();

  const payload = await buildIdlePayload(() => {
    return new Response(
      JSON.stringify({
        data: [{ id: 'qwen35-35b-a3b-q8_0', status: { value: 'unloaded' } }],
      }),
      { status: 200 }
    );
  });
  assert.match(payload, /llama_metrics_exporter_up 1/);
  assert.match(payload, /llama_metrics_exporter_idle 1/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total/);
});

test('buildMetricsPayload scrapes metrics for all available models', async () => {
  resetLastSuccessfulScrape();
  const calls = [];
  const fetchImpl = (url, _options) => {
    calls.push(url.toString());

    const pathname = new URL(url).pathname;
    if (pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } },
            { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: { value: 'unloaded' } },
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
        `llamacpp_tokens_predicted_total ${model === 'qwen35-35b-a3b-q8_0' ? 100 : 200}\n`,
      { status: 200 }
    );
  };

  const payload = await buildMetricsPayload(fetchImpl);

  assert.equal(calls.length, 3);
  assert.ok(calls.includes('http://llama-cpp:8000/models'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=qwen35-35b-a3b-q8_0&autoload=false'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=qwen3-coder-30b-a3b-instruct-q8_0&autoload=false'));
  assert.match(payload, /llama_metrics_exporter_idle 0/);
  assert.match(payload, /llama_metrics_exporter_discovered_models 2/);
  assert.match(payload, /llama_metrics_exporter_loaded_models 1/);
  assert.match(payload, /llama_metrics_exporter_metrics_scrape_up 1/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="qwen35-35b-a3b-q8_0"} 100/);
  assert.match(payload, /llamacpp_tokens_predicted_total\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 200/);
});

test('buildMetricsPayload attempts metrics scrape for all models even when none are loaded', async () => {
  resetLastSuccessfulScrape();
  const calls = [];
  const fetchImpl = (url, _options) => {
    calls.push(url.toString());
    const pathname = new URL(url).pathname;
    if (pathname === '/models') {
      return new Response(
        JSON.stringify({
          data: [
            { id: 'qwen35-35b-a3b-q8_0', status: { value: 'unloaded' } },
            { id: 'qwen3-coder-30b-a3b-instruct-q8_0', status: { value: 'unloaded' } },
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
  assert.ok(calls.includes('http://llama-cpp:8000/models'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=qwen35-35b-a3b-q8_0&autoload=false'));
  assert.ok(calls.includes('http://llama-cpp:8000/metrics?model=qwen3-coder-30b-a3b-instruct-q8_0&autoload=false'));
  assert.match(payload, /llama_metrics_exporter_idle 0/);
  assert.match(payload, /llama_metrics_exporter_loaded_models 0/);
  assert.match(payload, /llama_metrics_exporter_metrics_scrape_up 0/);
  assert.match(payload, /llama_metrics_exporter_model_up\{model="qwen35-35b-a3b-q8_0"} 0/);
  assert.match(payload, /llama_metrics_exporter_model_up\{model="qwen3-coder-30b-a3b-instruct-q8_0"} 0/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total\{/);
  assert.doesNotMatch(payload, /llamacpp_tokens_predicted_total\{/);
});

test('buildIdlePayload fetches the current /models list instead of using a stale cache', async () => {
  resetLastSuccessfulScrape();
  let modelsRequestCount = 0;

  const activeFetchImpl = (url) => {
    const parsedUrl = new URL(url);
    if (parsedUrl.pathname === '/models') {
      modelsRequestCount += 1;
      return new Response(
        JSON.stringify({
          data: [{ id: 'qwen35-35b-a3b-q8_0', status: { value: 'loaded' } }],
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

  await buildMetricsPayload(activeFetchImpl);

  const idlePayload = await buildIdlePayload((url) => {
    const parsedUrl = new URL(url);
    assert.equal(parsedUrl.pathname, '/models');
    modelsRequestCount += 1;
    return new Response(
      JSON.stringify({
        data: [{ id: 'panther-coder-large', status: { value: 'unloaded' } }],
      }),
      { status: 200 }
    );
  });

  assert.equal(modelsRequestCount, 2);
  assert.match(idlePayload, /llama_metrics_exporter_model_loaded\{model="panther-coder-large"} 0/);
  assert.doesNotMatch(idlePayload, /llama_metrics_exporter_model_loaded\{model="qwen35-35b-a3b-q8_0"} 0/);
});
