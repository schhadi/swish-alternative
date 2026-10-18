/**
 * UK phone numbers only in v1 (docs/SPEC.md section 1). Normalises common ways people type a UK number to E.164.
 * Accepts "07700 900123", "+44 7700 900123", "0044 7700 900123", "447700900123", with spaces, dashes, dots or brackets.
 * Returns null for anything else. The iOS app applies the same rules before hashing contacts, so keep them in sync.
 */
export function normaliseUKPhone(input: string): string | null {
  const compact = input.replace(/[\s\-().]/g, "");
  let national: string;
  if (/^\+44\d+$/.test(compact)) {
    national = compact.slice(3);
  } else if (/^0044\d+$/.test(compact)) {
    national = compact.slice(4);
  } else if (/^44\d{9,10}$/.test(compact)) {
    national = compact.slice(2);
  } else if (/^0\d+$/.test(compact)) {
    national = compact.slice(1);
  } else {
    return null;
  }
  // National significant number: 9 or 10 digits, never starting with 0.
  if (!/^[1-9]\d{8,9}$/.test(national)) {
    return null;
  }
  return `+44${national}`;
}

/** "+447700900123" -> "+44 7700 ***123" for log lines and UI hints. */
export function maskPhone(phoneE164: string): string {
  if (phoneE164.length < 7) return "***";
  return `${phoneE164.slice(0, 3)} ${phoneE164.slice(3, 7)} ***${phoneE164.slice(-3)}`;
}
