const TWO_H_MS = 2 * 60 * 60 * 1000;

/**
 * Load adherence rows, insert auto_taken for doses >2h past due with no log,
 * then merge statuses into occurrences.
 *
 * @param {import("@supabase/supabase-js").SupabaseClient} supabase
 * @param {string} userId
 * @param {any[]} occurrences
 */
export async function enrichOccurrencesWithAdherence(supabase, userId, occurrences) {
  const now = Date.now();
  if (!occurrences.length) return occurrences;

  const dueTimes = occurrences.map((o) => Date.parse(o.due_at_iso));
  const earliest = Math.min(...dueTimes) - TWO_H_MS;
  const latest = Math.max(...dueTimes) + TWO_H_MS;

  const { data: rows, error } = await supabase
    .from("medicine_dose_adherence")
    .select("occurrence_key,record_kind,recorded_at,due_at_iso")
    .eq("user_id", userId)
    .gte("due_at_iso", new Date(earliest).toISOString())
    .lte("due_at_iso", new Date(latest).toISOString());

  if (error) throw new Error(error.message);

  /** @type {Map<string, { record_kind: string, recorded_at: string }>} */
  const byKey = new Map(
    (rows || []).map((r) => [
      r.occurrence_key,
      { record_kind: r.record_kind, recorded_at: r.recorded_at },
    ]),
  );

  /** @type {any[]} */
  const autoCandidates = [];
  for (const o of occurrences) {
    const due = Date.parse(o.due_at_iso);
    if (byKey.has(o.id)) continue;
    if (now >= due + TWO_H_MS) {
      autoCandidates.push({
        user_id: userId,
        schedule_id: o.schedule_id,
        occurrence_key: o.id,
        due_at_iso: o.due_at_iso,
        record_kind: "auto_taken",
      });
    }
  }

  if (autoCandidates.length) {
    const keys = [...new Set(autoCandidates.map((r) => r.occurrence_key))];
    const { data: tied, error: exErr } = await supabase
      .from("medicine_dose_adherence")
      .select("occurrence_key,record_kind,recorded_at")
      .eq("user_id", userId)
      .in("occurrence_key", keys);
    if (exErr) throw new Error(exErr.message);
    for (const r of tied || []) {
      byKey.set(r.occurrence_key, { record_kind: r.record_kind, recorded_at: r.recorded_at });
    }

    const freshByKey = new Map();
    for (const r of autoCandidates) {
      if (!byKey.has(r.occurrence_key)) freshByKey.set(r.occurrence_key, r);
    }
    const fresh = [...freshByKey.values()];
    if (fresh.length) {
      await supabase.from("medicine_dose_adherence").insert(fresh);
    }

    const { data: again } = await supabase
      .from("medicine_dose_adherence")
      .select("occurrence_key,record_kind,recorded_at")
      .eq("user_id", userId)
      .in("occurrence_key", keys);
    for (const r of again || []) {
      byKey.set(r.occurrence_key, { record_kind: r.record_kind, recorded_at: r.recorded_at });
    }
  }

  return occurrences.map((o) => {
    const due = Date.parse(o.due_at_iso);
    const row = byKey.get(o.id);
    let adherence_status = "upcoming";
    let adherence_recorded_at = null;

    if (row) {
      adherence_recorded_at = row.recorded_at;
      adherence_status = row.record_kind === "user_taken" ? "taken" : "auto_taken";
    } else if (now > due) {
      adherence_status = "missed";
    }

    return {
      ...o,
      adherence_status,
      adherence_recorded_at,
    };
  });
}
