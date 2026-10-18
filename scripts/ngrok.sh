#!/usr/bin/env bash
# Expose the local backend so TrueLayer webhooks can reach it (Phase 2).
# Requires ngrok (https://ngrok.com). Copy the https URL it prints into PUBLIC_BASE_URL in backend/.env
# and register <url>/webhooks/truelayer in the TrueLayer Console.
set -euo pipefail
PORT="${PORT:-3000}"
exec ngrok http "$PORT"
