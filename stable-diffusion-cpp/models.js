// Paths that represent image-generation work and should reset the idle timer.
export const imageInferencePaths = new Set(['/v1/images/generations', '/v1/images/edits']);

// Paths that only enumerate models; treated as light activity (keeps the
// upstream considered "reachable" without counting as generation work).
export const activityPaths = new Set(['/models', '/v1/models']);

export function isImageInferencePath(pathname) {
  return typeof pathname === 'string' && imageInferencePaths.has(pathname);
}

export function normalizeModelsPayload(payload) {
  const data = Array.isArray(payload?.data) ? payload.data : [];
  const models = [];
  const seen = new Set();

  for (const item of data) {
    const id = typeof item?.id === 'string' ? item.id.trim() : '';
    if (!id || seen.has(id)) {
      continue;
    }

    seen.add(id);
    models.push({ id });
  }

  return models;
}
