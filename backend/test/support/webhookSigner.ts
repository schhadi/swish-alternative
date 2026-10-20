import { createPrivateKey, sign as cryptoSign } from "node:crypto";

/**
 * Signs a webhook the way TrueLayer's request-signing-v2 describes it (truelayer-signing/request-signing-v2.md):
 * a detached ES512 JWS whose header carries kid, tl_version "2", tl_headers and a jku, over
 * "POST <path>\\n" + "<Header>: <value>\\n" for each signed header + body. Written with node:crypto only, so the
 * tests check the official library's verify() against an independent signer rather than against itself.
 */
export interface WebhookSigningInput {
  privateKeyPem: string;
  kid: string;
  jku?: string;
  path: string;
  headers: Record<string, string>;
  body: string;
}

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

export function signWebhook(input: WebhookSigningInput): string {
  const headerNames = Object.keys(input.headers);
  const joseHeader: Record<string, string> = {
    alg: "ES512",
    kid: input.kid,
    tl_version: "2",
    tl_headers: headerNames.join(","),
    ...(input.jku ? { jku: input.jku } : {}),
  };
  const payload = `POST ${input.path}\n` + headerNames.map((name) => `${name}: ${input.headers[name]}\n`).join("") + input.body;
  const signingInput = `${base64url(JSON.stringify(joseHeader))}.${base64url(payload)}`;
  const signature = cryptoSign("sha512", Buffer.from(signingInput), { key: createPrivateKey(input.privateKeyPem), dsaEncoding: "ieee-p1363" });
  return `${base64url(JSON.stringify(joseHeader))}..${base64url(signature)}`;
}
