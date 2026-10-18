#!/usr/bin/env bash
# Start the backend on :3000 with live reload. First run: creates backend/.env from the example and applies migrations.
set -euo pipefail
cd "$(dirname "$0")/../backend"
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created backend/.env from .env.example (dev-only placeholder secrets)."
fi
if [ ! -d node_modules ]; then
  npm install
fi
npx prisma migrate deploy
exec npm run dev
