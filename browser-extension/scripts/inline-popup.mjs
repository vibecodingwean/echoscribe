export function inlinePopupAssets(html, css) {
  return html.replace(
    /\s*<link\s+rel=["']stylesheet["']\s+href=["']popup\.css["']\s*>/i,
    `\n  <style>${css}</style>`
  );
}
