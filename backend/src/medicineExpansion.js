/**
 * Expand persisted medicine_schedules rows into concrete upcoming occurrences.
 * Dates use calendar days in UTC; times are interpreted as UTC clock times ("HH:mm").
 */

export function ymFromDate(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function utcDayStart(d) {
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

/** @returns {IterableIterator<Date>} UTC midnight successive days inclusive */
function* eachUtcDayInclusive(start, endInclusive) {
  let t = utcDayStart(start);
  const end = utcDayStart(endInclusive);
  while (t <= end) {
    yield new Date(t);
    t += 24 * 60 * 60 * 1000;
  }
}

function parseDateOnly(s) {
  if (!s || typeof s !== "string") return null;
  const [y, m, d] = s.split("-").map((x) => Number(x));
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return null;
  return Date.UTC(y, m - 1, d);
}

/** @returns {boolean} ISO date string yyyy-mm-dd is on [start,end] inclusive */
function inRange(dayStr, startStr, endStr) {
  const t = parseDateOnly(dayStr);
  if (t === null) return false;
  const s = parseDateOnly(startStr);
  if (s !== null && t < s) return false;
  if (!endStr) return true;
  const e = parseDateOnly(endStr);
  return e === null ? true : t <= e;
}

function weekdayUtc(d) {
  return d.getUTCDay();
}

/**
 * @param {Record<string, any>} sch DB row snake_case from Postgres
 */
export function expandScheduleOccurrences(sch, { fromUtc, horizonDays }) {
  const out = [];
  const startStr = typeof sch.start_date === "string" ? sch.start_date : ymFromDate(new Date(fromUtc));
  let endInclusive = new Date(fromUtc);
  endInclusive.setUTCDate(endInclusive.getUTCDate() + Math.max(1, horizonDays));

  /** @type {string[]} */
  let times = [];
  if (Array.isArray(sch.time_points)) times = sch.time_points.map((x) => String(x));
  else if (typeof sch.time_points === "string") {
    try {
      const p = JSON.parse(sch.time_points);
      if (Array.isArray(p)) times = p.map((x) => String(x));
    } catch {
      times = [];
    }
  }

  if (times.length === 0) times = ["09:00"];

  /** @type {number[] | null} */
  let weekdays = null;
  if (sch.schedule_kind === "weekly" && sch.weekdays) {
    try {
      weekdays = Array.isArray(sch.weekdays) ? sch.weekdays.map(Number) : JSON.parse(JSON.stringify(sch.weekdays));
    } catch {
      weekdays = [];
    }
  }

  for (const d of eachUtcDayInclusive(new Date(fromUtc), endInclusive)) {
    const dayStr = ymFromDate(d);
    if (!inRange(dayStr, startStr, sch.end_date)) continue;

    if (sch.schedule_kind === "weekly" && weekdays && weekdays.length) {
      const wd = weekdayUtc(d);
      if (!weekdays.includes(wd)) continue;
    }

    if (sch.schedule_kind === "one_off" && dayStr !== startStr) continue;

    for (const hm of times) {
      const [hh, mm] = String(hm).split(":").map((x) => Number(x));
      if (!Number.isFinite(hh) || !Number.isFinite(mm)) continue;
      const when = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), hh, mm, 0, 0);
      if (when < fromUtc) continue;
      out.push({
        id: `${sch.id}:${dayStr}:${hm}`,
        schedule_id: sch.id,
        due_at_iso: new Date(when).toISOString(),
        medication_name: sch.medication_name,
        dosage_text: sch.dosage_text,
        meal_instruction: sch.meal_instruction,
        family_member_id: sch.family_member_id,
        prescription_id: sch.prescription_id,
        source: sch.source,
      });
    }
  }

  out.sort((a, b) => (a.due_at_iso < b.due_at_iso ? -1 : 1));
  return out;
}

/**
 * @param {Record<string, any>} sch schedule row from DB
 * @param {string} occurrenceKey synthetic id `${scheduleId}:${dayStr}:${hm}`
 */
export function findOccurrenceInSchedule(sch, occurrenceKey) {
  const key = String(occurrenceKey || "").trim();
  const m = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(\d{4}-\d{2}-\d{2}):(.+)$/i.exec(key);
  if (!m) return null;
  const dayStr = m[2];
  const t = parseDateOnly(dayStr);
  if (t === null) return null;
  const fromUtc = t - 48 * 60 * 60 * 1000;
  const list = expandScheduleOccurrences(sch, { fromUtc, horizonDays: 7 });
  return list.find((o) => o.id === key) ?? null;
}

export function flattenUpcomingFromRows(rows, { fromUtc = Date.now(), horizonDays = 3 } = {}) {
  /** @type {any[]} */
  const all = [];
  for (const r of rows || []) {
    all.push(...expandScheduleOccurrences(r, { fromUtc, horizonDays }));
  }
  return all;
}
