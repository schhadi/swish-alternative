#!/bin/sh
# Points this copy of the backend at Postgres: switches the datasource provider and swaps in the Postgres migration
# history (prisma/migrations-postgres). Run by the Docker image and CI's Postgres job, on a copy. Local development
# stays on SQLite; to undo it in a checkout, `git checkout prisma/schema.prisma prisma/migrations`.
set -eu
cd "$(dirname "$0")/.."
sed -i 's/provider = "sqlite"/provider = "postgresql"/' prisma/schema.prisma
grep -q 'provider = "postgresql"' prisma/schema.prisma
rm -rf prisma/migrations
cp -R prisma/migrations-postgres prisma/migrations
echo "Prisma now targets Postgres (schema provider and migrations switched)."
