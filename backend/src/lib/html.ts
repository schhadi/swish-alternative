/** Minimal server-rendered pages (dev approval page, invite and split links). No framework, no scripts. */

export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char] ?? char);
}

const STYLE = `body{font-family:-apple-system,system-ui,sans-serif;background:#F6F7F5;color:#141A17;margin:0;padding:24px}
main{max-width:420px;margin:0 auto;background:#fff;border-radius:20px;padding:24px;border:1px solid #EDF0EE}
h1{font-size:22px;line-height:1.25;margin:0 0 8px}p{color:#5F6B66;margin:0 0 16px;line-height:1.45}
.amount{font-size:40px;font-weight:800;letter-spacing:-2px;margin:12px 0}
.button,button{display:block;box-sizing:border-box;width:100%;height:58px;line-height:58px;border:0;border-radius:18px;font-size:17px;font-weight:700;margin-top:12px;text-align:center;text-decoration:none}
.primary{background:#0B6B54;color:#fff}.secondary{background:#EDF0EE;color:#141A17}
.small{font-size:14px;margin-top:16px}
@media (prefers-color-scheme: dark){body{background:#0F1412;color:#EEF2F0}main{background:#18201D;border-color:#26302C}p{color:#A3B0AA}.secondary{background:#26302C;color:#EEF2F0}}`;

/** A whole page. `title` and every interpolated value in `body` must already be escaped. */
export function htmlPage(title: string, body: string): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${title}</title>
<style>
${STYLE}
</style></head><body><main>
${body}
</main></body></html>`;
}

/** "Priya Patel" -> "Priya". Public pages show a first name only. */
export function firstName(displayName: string): string {
  return displayName.trim().split(/\s+/)[0] ?? "";
}
