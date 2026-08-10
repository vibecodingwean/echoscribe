export function getExtensionApi(scope = globalThis) {
  const api = scope.browser || scope.chrome;
  if (!api) throw new Error('WebExtension API is unavailable.');
  return api;
}
