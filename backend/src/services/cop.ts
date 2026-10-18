/**
 * Confirmation of Payee (docs/SPEC.md section 6). The interface is what a Pay.UK aggregator will implement;
 * v1 ships a fixture-driven fake for dev/sandbox and a stub that refuses in production.
 */
export type CopResult =
  | { status: "MATCH" }
  | { status: "CLOSE_MATCH"; accountHolderName: string }
  | { status: "NO_MATCH" };

export interface PayeeVerifier {
  verify(sortCode: string, accountNumber: string, accountHolderName: string): Promise<CopResult>;
}

/**
 * Fixtures:
 *  - sort code 999999 (any account number): NO_MATCH
 *  - known accounts below: MATCH when the name is exactly the registered one, CLOSE_MATCH when it differs only by
 *    case or spacing (the bank's version is returned), NO_MATCH for any other name
 *  - every other syntactically valid account: MATCH (so any dev account can be registered)
 * TrueLayer sandbox beneficiary accounts are added to the registry in Phase 2.
 */
export class FakePayeeVerifier implements PayeeVerifier {
  static readonly NO_MATCH_SORT_CODE = "999999";

  static readonly knownAccounts: ReadonlyMap<string, string> = new Map([
    ["040004:12345678", "Sam Okafor"],
    ["040004:87654321", "Priya Patel"],
    ["230580:11223344", "SOAS Hockey Club"],
  ]);

  async verify(sortCode: string, accountNumber: string, accountHolderName: string): Promise<CopResult> {
    if (sortCode === FakePayeeVerifier.NO_MATCH_SORT_CODE) {
      return { status: "NO_MATCH" };
    }
    const registered = FakePayeeVerifier.knownAccounts.get(`${sortCode}:${accountNumber}`);
    if (registered === undefined) {
      return { status: "MATCH" };
    }
    if (registered === accountHolderName.trim()) {
      return { status: "MATCH" };
    }
    if (looseKey(registered) === looseKey(accountHolderName)) {
      return { status: "CLOSE_MATCH", accountHolderName: registered };
    }
    return { status: "NO_MATCH" };
  }
}

export class NotImplementedPayeeVerifier implements PayeeVerifier {
  async verify(): Promise<CopResult> {
    throw new Error("Confirmation of Payee is not configured (COP_VERIFIER=none)");
  }
}

function looseKey(name: string): string {
  return name.toLowerCase().replace(/\s+/g, "");
}
