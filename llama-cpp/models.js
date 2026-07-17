export const largeModelIds = new Set([
  'Qwen3.6-27B-thinking',
  'Qwen3.6-27B',
  'Qwen3.6-35B-A3B-thinking',
  'Qwen3.6-35B-A3B',
  'Gemma-4-31B-thinking',
  'Gemma-4-31B',
  'DeepSeek-V4-Flash-thinking',
  'DeepSeek-V4-Flash',
]);

export function isLargeModelId(modelId) {
  return typeof modelId === 'string' && largeModelIds.has(modelId.trim());
}

export function normalizeModelsPayload(payload) {
  const data = Array.isArray(payload?.data) ? payload.data : [];
  const models = [];
  const seen = new Set();

  for (const item of data) {
    const id = typeof item?.id === 'string' ? item.id.trim() : '';
    if (!id || seen.has(id) || id.toLowerCase().includes('embedding')) {
      continue;
    }

    const statusValue = typeof item?.status?.value === 'string' ? item.status.value.trim().toLowerCase() : 'unknown';
    seen.add(id);
    models.push({ id, status: statusValue });
  }

  return models;
}

export function isVariantOf(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') {
    return false;
  }
  const trimA = a.trim();
  const trimB = b.trim();
  if (trimA === trimB) {
    return false;
  }
  return trimA === `${trimB}-thinking` || trimB === `${trimA}-thinking`;
}
