export function getExtensionApi(scope = globalThis) {
  const api = scope.chrome;
  if (!api) throw new Error('Chrome extension API is unavailable.');
  return api;
}
