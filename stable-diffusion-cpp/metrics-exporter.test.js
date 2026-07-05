import assert from 'node:assert/strict';
import test from 'node:test';

import { buildMetricsLines, escapeLabelValue, fetchModelsList, queryManagerStatus } from './metrics-exporter.js';

test('escapeLabelValue escapes backslashes, quotes, and newlines', () => {
  assert.equal(escapeLabelValue('a"b\\c\nd'), 'a\\"b\\\\c\\nd');
});

test('queryManagerStatus returns parsed status when the manager responds', async () => {
  const status = await queryManagerStatus((url) => {
    assert.equal(url, 'http://sd-manager:8000/status');
    return new Response(JSON.stringify({ active: false, activeProxyRequests: 2, lastActivityAt: 1000 }), {
      status: 200,
    });
  });

  assert.deepEqual(status, { active: false, activeProxyRequests: 2, lastActivityAt: 1000, reachable: true });
});

test('queryManagerStatus falls back to active/unreachable when the manager errors', async () => {
  const status = await queryManagerStatus(() => {
    throw new Error('connection refused');
  });

  assert.deepEqual(status, { active: true, activeProxyRequests: 0, lastActivityAt: 0, reachable: false });
});

test('fetchModelsList normalizes the /v1/models payload', async () => {
  const result = await fetchModelsList((url) => {
    assert.equal(url, 'http://stable-diffusion-cpp:8000/v1/models');
    return new Response(JSON.stringify({ data: [{ id: 'ideogram-4' }, { id: 'ideogram-4' }, { id: '' }] }), {
      status: 200,
    });
  });

  assert.deepEqual(result, { models: [{ id: 'ideogram-4' }], reachable: true });
});

test('fetchModelsList reports unreachable when sd-server errors', async () => {
  const result = await fetchModelsList(() => {
    throw new Error('connection refused');
  });

  assert.deepEqual(result, { models: [], reachable: false });
});

test('buildMetricsLines reports idle only when the manager is reachable and inactive', () => {
  const lines = buildMetricsLines(
    { active: false, activeProxyRequests: 0, lastActivityAt: 2000, reachable: true },
    { models: [{ id: 'ideogram-4' }], reachable: true }
  );

  assert.ok(lines.includes('sd_metrics_exporter_idle 1'));
  assert.ok(lines.includes('sd_metrics_exporter_server_up 1'));
  assert.ok(lines.includes('sd_metrics_exporter_manager_up 1'));
  assert.ok(lines.includes('sd_metrics_exporter_active_requests 0'));
  assert.ok(lines.includes('sd_metrics_exporter_last_activity_timestamp_seconds 2'));
  assert.ok(lines.includes('sd_metrics_exporter_discovered_models 1'));
  assert.ok(lines.includes('sd_metrics_exporter_model_available{model="ideogram-4"} 1'));
});

test('buildMetricsLines never reports idle while requests are in flight', () => {
  const lines = buildMetricsLines(
    { active: true, activeProxyRequests: 3, lastActivityAt: 5000, reachable: true },
    { models: [], reachable: true }
  );

  assert.ok(lines.includes('sd_metrics_exporter_idle 0'));
  assert.ok(lines.includes('sd_metrics_exporter_active_requests 3'));
});

test('buildMetricsLines is not idle when the manager is unreachable', () => {
  const lines = buildMetricsLines(
    { active: true, activeProxyRequests: 0, lastActivityAt: 0, reachable: false },
    { models: [], reachable: false }
  );

  assert.ok(lines.includes('sd_metrics_exporter_idle 0'));
  assert.ok(lines.includes('sd_metrics_exporter_manager_up 0'));
  assert.ok(lines.includes('sd_metrics_exporter_server_up 0'));
});
