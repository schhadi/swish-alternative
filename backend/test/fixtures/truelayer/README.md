# TrueLayer signing test resources

Copied unchanged from TrueLayer's official `truelayer-signing` repository (`test-resources/`, Apache-2.0 / MIT),
https://github.com/TrueLayer/truelayer-signing. They are test keys published by TrueLayer, never used for anything real.

- `ec512-private.pem` / `ec512-public.pem`: ES512 key pair, kid `45fc75cf-5649-4134-84b3-192c2c78e990`.
- `jwks.json`: a `.well-known/jwks` response that includes the public key above.
- `webhook-signature.txt`: a recorded webhook `Tl-Signature` (jku `https://webhooks.truelayer.com/.well-known/jwks`)
  for `POST /tl-webhook` with headers `X-Tl-Webhook-Timestamp: 2021-11-29T11:42:55Z`, `Content-Type: application/json`
  and body `{"event_type":"example","event_id":"18b2842b-a57b-4887-a0a6-d3c7c36f1020"}`.
- `tl-signature.txt`: a recorded request signature for `POST /merchant_accounts/a61acaef-ee05-4077-92f3-25543a11bd8d/sweeping`
  with `Idempotency-Key: idemp-2076717c-9005-4811-a321-9e0787fa0382` and body
  `{"currency":"GBP","max_amount_in_minor":5000000,"name":"Foo???"}`.
