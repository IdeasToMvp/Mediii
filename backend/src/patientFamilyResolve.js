/**
 * Match AI patient_name to a saved family member; if no match and members exist, pick one at random.
 */

function normalizeName(s) {
  return String(s || "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokens(s) {
  const n = normalizeName(s);
  if (!n) return [];
  return n.split(" ").filter((t) => t.length > 1);
}

/**
 * @param {string | null | undefined} patientName
 * @param {Array<Record<string, any>>} members rows from family_members
 * @returns {{ family_member_id: string | null, mode: 'matched' | 'random' | 'none' }}
 */
export function resolvePatientFamilyMember(patientName, members) {
  const list = Array.isArray(members) ? members : [];
  if (list.length === 0) {
    return { family_member_id: null, mode: "none" };
  }

  const patientNorm = normalizeName(patientName);
  if (!patientNorm) {
    return { family_member_id: null, mode: "none" };
  }

  const ptoks = tokens(patientName);

  for (const mem of list) {
    const dn = normalizeName(mem.display_name);
    if (!dn) continue;
    if (dn === patientNorm) {
      return { family_member_id: mem.id, mode: "matched" };
    }
    if (patientNorm.includes(dn) || dn.includes(patientNorm)) {
      return { family_member_id: mem.id, mode: "matched" };
    }
  }

  for (const mem of list) {
    const mtoks = tokens(mem.display_name);
    if (mtoks.length === 0) continue;
    for (const t of ptoks) {
      if (mtoks.includes(t)) {
        return { family_member_id: mem.id, mode: "matched" };
      }
    }
  }

  const pick = list[Math.floor(Math.random() * list.length)];
  return { family_member_id: pick.id, mode: "random" };
}
