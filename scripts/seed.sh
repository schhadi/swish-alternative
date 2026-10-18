#!/usr/bin/env bash
# Seed the dev database with a few registered users. Safe to run repeatedly.
set -euo pipefail
cd "$(dirname "$0")/../backend"
npm run seed
