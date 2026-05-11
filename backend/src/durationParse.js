/**
 * Extract a finite course length in CALENDAR DAYS from vague prescription text.
 * Returns null → open-ended reminders (until user edits/removes schedule).
 */

export function parseDurationDays(raw) {
  if (raw == null) return null;
  const s = String(raw).toLowerCase().trim().replace(/\s+/g, " ");
  if (
    !s ||
    /indef|indefinite|lifelong|lifetime|perm|perm\.|perm\b|continuous|chronic\s+course|as\s+needed|prn\b|until\s+review|until\s+follow|ongoing|not\s+specified|—|–|-\s*$/.test(
      s,
    )
  ) {
    return null;
  }

  const tryNum = (n) => {
    const v = Number(n);
    return Number.isFinite(v) && v > 0 && v < 10000 ? Math.trunc(v) : null;
  };

  let m = s.match(/(\d+)\s*(?:weeks?|wks?)\b/);
  if (m) {
    const w = tryNum(m[1]);
    return w == null ? null : w * 7;
  }

  m = s.match(/(\d+)\s*(?:months?|mos?)\b/);
  if (m) {
    const mo = tryNum(m[1]);
    return mo == null ? null : mo * 30;
  }

  m = s.match(/(\d+)\s*(?:days?|d)\b/);
  if (m) return tryNum(m[1]);

  m = s.match(/\b(\d+)\s*x\s*(?:daily|per day|a day)\b/);
  if (m) return tryNum(m[1]);

  m = s.match(/(?:for|x)\s*(\d+)\s*(?:day|days|d)\b/);
  if (m) return tryNum(m[1]);

  m = s.match(/^\s*(\d+)\s*$/);
  if (m) return tryNum(m[1]);

  m = s.match(/\b(\d+)\b/);
  if (m) {
    const n = tryNum(m[1]);
    if (n != null && n <= 180) return n;
  }

  return null;
}
