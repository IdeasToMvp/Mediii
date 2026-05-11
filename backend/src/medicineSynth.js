import { parseDurationDays } from "./durationParse.js";

function addDaysToIso(isoDate, deltaDays) {
  const [y, mo, d] = isoDate.split("-").map((x) => Number(x));
  if (!Number.isFinite(y) || !Number.isFinite(mo) || !Number.isFinite(d)) return null;
  const dt = new Date(Date.UTC(y, mo - 1, d));
  dt.setUTCDate(dt.getUTCDate() + deltaDays);
  return dt.toISOString().slice(0, 10);
}

function todayIsoUtc() {
  return new Date().toISOString().slice(0, 10);
}

function parseStartDateFromRx(prescriptionDate) {
  if (typeof prescriptionDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(prescriptionDate.trim())) {
    return prescriptionDate.trim();
  }
  return todayIsoUtc();
}

/**
 * Derive clock times (HH:mm) from medication free-text fields.
 * @param {Record<string, any>} m
 * @param {string[]} defaultTimes
 */
export function deriveTimePoints(m, defaultTimes) {
  const ins = String(m.instructions ?? "").toLowerCase();
  const freq = String(m.frequency ?? "").toLowerCase();
  const base = Array.isArray(defaultTimes) && defaultTimes.length ? defaultTimes.map((x) => String(x)) : ["09:00"];

  if (/before breakfast|morning|am\b|empty stomach/.test(ins) || /morning|qd\s*am|once.*morning/.test(freq)) {
    return ["08:00"];
  }
  if (/with lunch|after lunch|noon|afternoon/.test(ins) || /lunch/.test(freq)) {
    return ["13:00"];
  }
  if (/with dinner|after dinner|evening|night|bedtime|hs\b|pm\b/.test(ins) || /night|hs|evening/.test(freq)) {
    return ["20:00"];
  }
  if (/three times|\btid\b|thrice/i.test(freq) || /three times/.test(ins)) {
    return ["08:00", "14:00", "21:00"];
  }
  if (/four times|\bqid\b|q\.?i\.?d\b/.test(freq)) {
    return ["08:00", "12:30", "18:00", "22:00"];
  }
  if (/two times|\bbid\b|twice\s+daily|\bb\.?i\.?d\b/.test(freq) || /twice\s+daily/.test(ins)) {
    return ["08:00", "20:00"];
  }
  if (/once\s+daily|\bod\b|^od$|every\s*24|single\s+dose/.test(freq)) {
    return ["09:00"];
  }

  return base.slice();
}

/**
 * Build schedule insert rows (not yet written) from a saved prescription row.
 * @param {Record<string, any>} rx
 * @param {string} userId
 * @param {{ family_member_id?: string | null, default_times?: string[], start_date?: string }} options
 */
export function buildMedicineScheduleInserts(rx, userId, options = {}) {
  const meds = Array.isArray(rx.medications) ? rx.medications : [];
  const pid = rx.id;
  if (!pid || !userId) return [];

  const startDate = options.start_date ?? parseStartDateFromRx(rx.prescription_date);
  const fm =
    typeof options.family_member_id === "string" && options.family_member_id.trim().length > 0 ?
      options.family_member_id.trim()
    : null;

  const defaultTimes = Array.isArray(options.default_times) ? options.default_times.map((x) => String(x)) : ["09:00"];

  /** @type {Record<string, any>[]} */
  const rows = [];

  for (let i = 0; i < meds.length; i += 1) {
    const m = meds[i] || {};
    const nameRaw = typeof m.name === "string" ? m.name.trim() : "";
    if (!nameRaw) continue;

    const times = deriveTimePoints(m, defaultTimes);
    const durDays = parseDurationDays(m.duration);
    /** @type {string | null} */
    let endDate = null;
    if (durDays != null && durDays > 0 && startDate) {
      endDate = addDaysToIso(startDate, durDays - 1);
    }

    const dosage = typeof m.dosage === "string" ? m.dosage : null;

    /** @type {string | null} */
    let meal = null;
    if (typeof m.instructions === "string" && m.instructions.trim().length > 0) meal = m.instructions.trim();

    rows.push({
      user_id: userId,
      family_member_id: fm,
      source: "prescription_generated",
      prescription_id: pid,
      medication_line_index: i,
      medication_name: nameRaw,
      dosage_text: dosage,
      meal_instruction: meal,
      schedule_kind: "daily",
      time_points: times,
      start_date: startDate,
      end_date,
      timezone: typeof options.timezone === "string" ? options.timezone : "UTC",
      updated_at: new Date().toISOString(),
    });
  }

  return rows;
}
