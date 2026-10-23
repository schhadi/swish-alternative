# syntax=docker/dockerfile:1
# The Quid backend as a container, for the hosted sandbox on Fly.io (docs/RUNBOOK.md). It runs on Postgres:
# scripts/use-postgres.sh switches the datasource and the migration history before the Prisma client is generated.

FROM node:20-bookworm-slim AS build
# Prisma's engines need OpenSSL.
RUN apt-get update -qq && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
COPY prisma ./prisma
COPY scripts ./scripts
RUN sh scripts/use-postgres.sh
# Installs everything (postinstall generates the Postgres client), builds, then drops the dev tools.
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:20-bookworm-slim
RUN apt-get update -qq && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build --chown=node:node /app/package.json /app/package-lock.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/prisma ./prisma
COPY --from=build --chown=node:node /app/dist ./dist
USER node
ENV HOST=0.0.0.0 PORT=3000
EXPOSE 3000
CMD ["node", "dist/server.js"]
