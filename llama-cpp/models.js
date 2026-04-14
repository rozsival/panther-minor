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
