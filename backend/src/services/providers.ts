import { env } from "../config.js";

/** A bank the payer can be sent to for authorisation. Shape mirrors what GET /providers returns to the app. */
export interface Provider {
  id: string;
  displayName: string;
  logoUrl: string | null;
}

export interface ProviderSource {
  list(): Promise<Provider[]>;
}

/**
 * Phase 1 stand-in for the TrueLayer providers API. Ids follow TrueLayer's "ob-<bank>" convention and are validated
 * against the real list when the TrueLayer client lands in Phase 2 (docs/DECISIONS.md). Logos arrive with that too.
 */
export const GB_PROVIDERS: readonly Provider[] = [
  { id: "ob-monzo", displayName: "Monzo", logoUrl: null },
  { id: "ob-starling", displayName: "Starling", logoUrl: null },
  { id: "ob-barclays", displayName: "Barclays", logoUrl: null },
  { id: "ob-lloyds", displayName: "Lloyds", logoUrl: null },
  { id: "ob-halifax", displayName: "Halifax", logoUrl: null },
  { id: "ob-bos", displayName: "Bank of Scotland", logoUrl: null },
  { id: "ob-natwest", displayName: "NatWest", logoUrl: null },
  { id: "ob-rbs", displayName: "Royal Bank of Scotland", logoUrl: null },
  { id: "ob-hsbc", displayName: "HSBC", logoUrl: null },
  { id: "ob-first-direct", displayName: "first direct", logoUrl: null },
  { id: "ob-santander", displayName: "Santander", logoUrl: null },
  { id: "ob-nationwide", displayName: "Nationwide", logoUrl: null },
  { id: "ob-tsb", displayName: "TSB", logoUrl: null },
  { id: "ob-revolut", displayName: "Revolut", logoUrl: null },
  { id: "ob-chase", displayName: "Chase", logoUrl: null },
  { id: "ob-virgin-money", displayName: "Virgin Money", logoUrl: null },
  { id: "ob-co-op", displayName: "The Co-operative Bank", logoUrl: null },
];

export const SANDBOX_MOCK_PROVIDER: Provider = {
  id: "mock-payments-gb-redirect",
  displayName: "Mock Bank (sandbox)",
  logoUrl: null,
};

export class StaticProviderSource implements ProviderSource {
  constructor(private readonly includeSandboxMock: boolean = env.TRUELAYER_ENV === "sandbox") {}

  async list(): Promise<Provider[]> {
    return this.includeSandboxMock ? [...GB_PROVIDERS, SANDBOX_MOCK_PROVIDER] : [...GB_PROVIDERS];
  }
}

/** Display name for a stored providerId, or null when unknown (the app then shows "Your bank"). */
export function providerDisplayName(providerId: string | null | undefined, providers: readonly Provider[]): string | null {
  if (!providerId) return null;
  return providers.find((provider) => provider.id === providerId)?.displayName ?? null;
}
