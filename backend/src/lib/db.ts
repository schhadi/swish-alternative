import { PrismaClient } from "@prisma/client";

// Single Prisma client for the process. Prisma reads DATABASE_URL from the environment.
export const prisma = new PrismaClient();

/** Cheap connectivity probe that works on SQLite and Postgres alike. */
export async function pingDatabase(): Promise<boolean> {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}
