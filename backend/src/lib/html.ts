import type { FastifyReply } from "fastify";

/** Minimal server-rendered pages (dev approval page, invite and split links, collection pay page). No framework, no scripts. */

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
label{display:block;font-weight:600;font-size:15px;margin:18px 0 6px}
input{box-sizing:border-box;width:100%;height:50px;border:1px solid #DDE3DF;border-radius:14px;padding:0 14px;font-size:17px;background:#fff;color:#141A17}
.error{background:#FDECEC;color:#9B2C2C;border-radius:14px;padding:12px 14px;margin:12px 0;font-weight:600}
.status{display:inline-block;border-radius:999px;padding:4px 12px;font-size:14px;font-weight:700;margin-bottom:8px}
.paid{background:#E3F3EC;color:#084D3D}.pending{background:#FDF1DF;color:#9A5A12}.failed{background:#FDECEC;color:#9B2C2C}
@media (prefers-color-scheme: dark){body{background:#0F1412;color:#EEF2F0}main{background:#18201D;border-color:#26302C}p{color:#A3B0AA}.secondary{background:#26302C;color:#EEF2F0}input{background:#0F1412;color:#EEF2F0;border-color:#26302C}}`;

/** A whole page. `title` and every interpolated value in `body` must already be escaped. */
export function htmlPage(title: string, body: string, options: { refreshSeconds?: number; refreshUrl?: string } = {}): string {
  const target = options.refreshUrl ? `; url=${escapeHtml(options.refreshUrl)}` : "";
  const refresh = options.refreshSeconds ? `\n<meta http-equiv="refresh" content="${options.refreshSeconds}${target}">` : "";
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">${refresh}
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

/**
 * Sends a public page: no caching, no referrer, no scripts, never framed. `forms` lets the page post a form (the
 * collection pay page, whose answer redirects to the bank's own page, so form-action is left open for that redirect);
 * `title` is plain text and escaped here.
 */
export function sendHtmlPage(
  reply: FastifyReply,
  status: number,
  title: string,
  body: string,
  options: { forms?: boolean; refreshSeconds?: number; refreshUrl?: string } = {},
) {
  const csp = ["default-src 'none'", "style-src 'unsafe-inline'", "base-uri 'none'", "frame-ancestors 'none'", ...(options.forms ? [] : ["form-action 'none'"])].join("; ");
  return reply
    .status(status)
    .header("cache-control", "no-store")
    .header("referrer-policy", "no-referrer")
    .header("x-content-type-options", "nosniff")
    .header("content-security-policy", csp)
    .type("text/html; charset=utf-8")
    .send(htmlPage(escapeHtml(title), body, { refreshSeconds: options.refreshSeconds, refreshUrl: options.refreshUrl }));
}
