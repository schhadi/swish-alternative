/**
 * Serialises async work per key inside this process. Used so two payments from the same payer cannot both pass the
 * rolling-limit check before either is written (docs/DECISIONS.md #61). One backend process is the v1 deployment;
 * a multi-instance deployment needs a database lock here instead (Phase 5 go-live checklist).
 */
const tails = new Map<string, Promise<unknown>>();

export async function withKeyedLock<T>(key: string, work: () => Promise<T>): Promise<T> {
  const previous = tails.get(key) ?? Promise.resolve();
  const run = previous.then(work, work);
  const settled = run.then(
    () => undefined,
    () => undefined,
  );
  tails.set(key, settled);
  try {
    return await run;
  } finally {
    if (tails.get(key) === settled) tails.delete(key);
  }
}
