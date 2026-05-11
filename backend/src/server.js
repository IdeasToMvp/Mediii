import "dotenv/config";
import cors from "cors";
import express from "express";
import multer from "multer";
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "crypto";
import path from "path";
import OpenAI from "openai";
import { analyzeMedicalDocumentImage } from "./openaiMedicalDocument.js";
import { flattenUpcomingFromRows } from "./medicineExpansion.js";
import { buildMedicineScheduleInserts, addDaysToIso } from "./medicineSynth.js";
import { resolvePatientFamilyMember } from "./patientFamilyResolve.js";

const PORT = Number(process.env.PORT) || 3200;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_ANON_KEY");
  process.exit(1);
}
if (!OPENAI_API_KEY) {
  console.error("Missing OPENAI_API_KEY");
  process.exit(1);
}

const UPLOAD_MAX_BYTES = 10 * 1024 * 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: UPLOAD_MAX_BYTES },
});

const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));

const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

function supabaseForUser(jwt) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}

async function requireUser(req, res, next) {
  const hdr = req.headers.authorization || "";
  const token = hdr.startsWith("Bearer ") ? hdr.slice(7).trim() : null;
  if (!token) {
    res.status(401).json({ error: "Missing Bearer token (Supabase access_token)" });
    return;
  }
  const supabase = supabaseForUser(token);
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();
  if (error || !user) {
    res.status(401).json({ error: "Invalid or expired session" });
    return;
  }
  req.supabase = supabase;
  req.user = user;
  next();
}

function inferDisplayName(user) {
  const meta =
    typeof user?.user_metadata === "object" && user.user_metadata !== null ? user.user_metadata : {};
  const full =
    typeof meta.full_name === "string" && meta.full_name.trim().length ?
      meta.full_name.trim()
    : null;
  if (full) return full.split(/\s+/)[0];
  const email = typeof user?.email === "string" ? user.email : "";
  const local = email.split("@")[0] || "";
  return local || "Friend";
}

async function bootstrapUserContext(supabase, user) {
  await supabase.rpc("ensure_user_entitlements");
  await supabase.rpc("sync_ai_usage_month");
  const { data: profile } = await supabase.from("user_profiles").select("*").maybeSingle();
  if (!profile) {
    await supabase
      .from("user_profiles")
      .upsert({
        user_id: user.id,
        display_name: inferDisplayName(user),
        timezone: "UTC",
        updated_at: new Date().toISOString(),
      })
      .select("*")
      .maybeSingle();
  }
}

async function peekAiExtractionsBudget(supabase) {
  await supabase.rpc("ensure_user_entitlements");
  await supabase.rpc("sync_ai_usage_month");

  const { data: ue, error: ueErr } = await supabase.from("user_entitlements").select("*").maybeSingle();
  if (ueErr || !ue) return { unlimited: false, used: 0, limit: 0, denied: false };

  const { data: plan, error: pErr } = await supabase
    .from("subscription_plans")
    .select("*")
    .eq("slug", ue.plan_slug)
    .maybeSingle();
  if (pErr || !plan) return { unlimited: true, used: ue.ai_extractions_used, limit: null, denied: false };

  const limit = Number(plan.monthly_ai_extractions);
  if (!Number.isFinite(limit) || limit < 0) {
    return { unlimited: true, used: ue.ai_extractions_used, limit: null, denied: false, plan_slug: ue.plan_slug };
  }
  return {
    unlimited: false,
    used: Number(ue.ai_extractions_used) || 0,
    limit,
    denied: ue.ai_extractions_used > limit,
    plan_slug: ue.plan_slug,
  };
}

async function consumeAiExtraction(supabase) {
  const { data: payload, error } = await supabase.rpc("increment_ai_extractions", { amount: 1 });
  if (error) throw error;
  try {
    return typeof payload === "string" ? JSON.parse(payload) : payload ?? { allowed: false };
  } catch {
    return { allowed: false, reason: "invalid_rpc_payload" };
  }
}

async function assertFamilySeatAvailable(supabase) {
  const { data: payload, error } = await supabase.rpc("can_add_family_member");
  if (error) throw error;
  const obj = typeof payload === "string" ? JSON.parse(payload) : payload;
  if (!obj?.allowed) {
    const err = new Error(obj?.reason || "family_quota");
    err.code = obj?.reason;
    err.detail = obj;
    throw err;
  }
}

function coerceRpcJson(payload) {
  try {
    return typeof payload === "string" ? JSON.parse(payload) : payload;
  } catch {
    return null;
  }
}

async function validateFamilyOwnership(supabase, familyMemberId) {
  const { data, error } = await supabase
    .from("family_members")
    .select("id")
    .eq("id", familyMemberId)
    .maybeSingle();
  return !error && Boolean(data?.id);
}

async function fetchFamilyMembersForUser(supabase, userId) {
  const { data, error } = await supabase
    .from("family_members")
    .select("*")
    .eq("owner_user_id", userId)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data || [];
}

function planSlugFromPeek(peek) {
  return typeof peek?.plan_slug === "string" && peek.plan_slug.trim() ? peek.plan_slug.trim() : "free";
}

function mimeAllowedMedicalUpload(planSlug, mimeRaw) {
  const mime = (mimeRaw || "").toLowerCase();
  if (/^image\/(jpeg|png|webp|gif)$/.test(mime)) return true;
  const paid = planSlug === "plus" || planSlug === "pro";
  return paid && mime === "application/pdf";
}

function normalizeSourceStoragePath(userId, pathRaw) {
  const p = typeof pathRaw === "string" ? pathRaw.trim() : "";
  if (!p) return null;
  const first = p.split("/")[0];
  if (first !== userId) return null;
  return p;
}

async function insertMedicineSchedulesBulk(supabase, rows) {
  if (!rows?.length) return [];
  const { data, error } = await supabase.from("medicine_schedules").insert(rows).select("*");
  if (error) throw error;
  return data || [];
}

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "medibuddy-api" });
});

app.get("/api/me", requireUser, async (req, res) => {
  try {
    await bootstrapUserContext(req.supabase, req.user);
    const { data: profile } = await req.supabase.from("user_profiles").select("*").maybeSingle();

    await req.supabase.rpc("sync_ai_usage_month");
    const budget = await peekAiExtractionsBudget(req.supabase);

    const { data: ue } = await req.supabase.from("user_entitlements").select("*").maybeSingle();

    let planMeta = null;
    if (ue?.plan_slug) {
      const { data: pm } = await req.supabase.from("subscription_plans").select("*").eq("slug", ue.plan_slug).maybeSingle();
      planMeta = pm;
    }

    const { count: fmCount /* family members */ } = await req.supabase
      .from("family_members")
      .select("id", { count: "exact", head: true });

    res.json({
      user: {
        id: req.user.id,
        email: req.user.email,
      },
      profile: profile ?? null,
      entitlement: ue ?? null,
      plan:
        planMeta ?
          {
            ...planMeta,
            ai_budget: {
              unlimited: budget.unlimited === true,
              used: budget.used,
              monthly_limit: budget.limit,
            },
            family_slots_used: fmCount ?? 0,
            upload_caps: {
              max_bytes: UPLOAD_MAX_BYTES,
              allows_multi_pick: ue?.plan_slug === "plus" || ue?.plan_slug === "pro",
              allows_pdf: ue?.plan_slug === "plus" || ue?.plan_slug === "pro",
              image_types: "JPEG, PNG, WebP, GIF",
              paid_label: "Plus / Pro",
            },
          }
        : null,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "profile_load_failed", detail: String(e.message || e) });
  }
});

const ALLOWED_PROFILE_GENDERS = new Set(["female", "male", "non_binary", "prefer_not_say", "other"]);

app.patch("/api/me/profile", requireUser, async (req, res) => {
  try {
    await bootstrapUserContext(req.supabase, req.user);
    const body = req.body || {};
    const patch = { updated_at: new Date().toISOString() };

    if ("display_name" in body) {
      if (body.display_name === null || body.display_name === undefined) {
        patch.display_name = null;
      } else if (typeof body.display_name === "string") {
        const t = body.display_name.trim();
        patch.display_name = t.length ? t.slice(0, 200) : null;
      }
    }

    if ("birth_year" in body) {
      if (body.birth_year === null) {
        patch.birth_year = null;
      } else {
        const y =
          typeof body.birth_year === "number" ?
            body.birth_year
          : typeof body.birth_year === "string" ?
            Number(body.birth_year)
          : NaN;
        const cy = new Date().getUTCFullYear();
        if (!Number.isFinite(y) || y % 1 !== 0 || y < 1900 || y > cy) {
          return res.status(400).json({ error: "birth_year must be a whole year between 1900 and the current year." });
        }
        patch.birth_year = Math.trunc(y);
      }
    }

    if ("gender" in body) {
      if (body.gender === null || body.gender === undefined || body.gender === "") {
        patch.gender = null;
      } else if (typeof body.gender === "string") {
        const g = body.gender.trim().toLowerCase();
        if (!ALLOWED_PROFILE_GENDERS.has(g)) {
          return res.status(400).json({ error: "Invalid gender. Use female, male, non_binary, prefer_not_say, or other." });
        }
        patch.gender = g;
      }
    }

    if ("timezone" in body && typeof body.timezone === "string") {
      const tz = body.timezone.trim();
      if (tz.length) patch.timezone = tz.slice(0, 100);
    }

    const meaningful = Object.keys(patch).filter((k) => k !== "updated_at");
    if (meaningful.length === 0) {
      const { data: p } = await req.supabase.from("user_profiles").select("*").maybeSingle();
      return res.json({ profile: p });
    }

    const { error: upErr } = await req.supabase.from("user_profiles").update(patch).eq("user_id", req.user.id);
    if (upErr) return res.status(400).json({ error: upErr.message });

    const { data: fresh } = await req.supabase.from("user_profiles").select("*").maybeSingle();
    res.json({ profile: fresh });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "profile_update_failed", detail: String(e.message || e) });
  }
});

app.get("/api/subscription/plans", requireUser, async (req, res) => {
  const { data, error } = await req.supabase.from("subscription_plans").select("*").order("max_family_members", {
    ascending: true,
  });
  if (error) return res.status(400).json({ error: error.message });
  res.json({ plans: data || [] });
});

/**
 * Persist original bytes to private storage ({user_id}/{uuid}.ext).
 * Free: images only (jpeg, png, webp, gif). Paid (plus/pro): also application/pdf.
 */
app.post("/api/prescriptions/upload-source", requireUser, upload.single("file"), async (req, res) => {
  try {
    if (!req.file) {
      res.status(400).json({ error: 'multipart field "file" is required' });
      return;
    }

    await bootstrapUserContext(req.supabase, req.user);
    const peek = await peekAiExtractionsBudget(req.supabase);
    const planSlug = planSlugFromPeek(peek);

    const mime = (req.file.mimetype || "application/octet-stream").trim();
    if (!mimeAllowedMedicalUpload(planSlug, mime)) {
      return res.status(400).json({
        error:
          planSlug === "free" ?
            "Free plan accepts JPEG/PNG/WebP/GIF only. Plus or Pro can also upload PDFs."
          : "Unsupported file type. Allowed: jpeg, png, webp, gif, pdf.",
        plan_slug: planSlug,
        max_bytes: UPLOAD_MAX_BYTES,
      });
    }

    const extGuess =
      mime === "application/pdf"
        ? ".pdf"
      : mime.includes("webp")
        ? ".webp"
      : mime.includes("png")
        ? ".png"
      : mime.includes("gif")
        ? ".gif"
        : ".jpg";

    let origName =
      typeof req.file.originalname === "string" && req.file.originalname.trim() ?
        req.file.originalname.trim().slice(0, 240)
      : `document${extGuess}`;

    const extFromName = path.extname(origName).toLowerCase();
    const allowedFromName = /^\.(jpe?g|png|webp|gif|pdf)$/.test(extFromName);
    const suffix = allowedFromName ? extFromName : extGuess;

    const objectPath = `${req.user.id}/${randomUUID()}${suffix}`;

    const { error: upErr } = await req.supabase.storage.from("prescription-sources").upload(objectPath, req.file.buffer, {
      contentType: mime,
      upsert: false,
    });

    if (upErr) {
      console.error(upErr);
      return res.status(500).json({ error: "storage_upload_failed", detail: upErr.message });
    }

    res.json({
      storage_path: objectPath,
      mime,
      original_name: origName,
      max_bytes: UPLOAD_MAX_BYTES,
      plan_slug: planSlug,
      allowed_notice:
        planSlug === "free" ?
          "Free: one image at a time · JPEG/PNG/WebP/GIF · max 10 MB. AI analyzes photos."
        : "Plus/Pro: multi-select images · PDF uploads · images + PDF · max 10 MB per file. AI analyzes photo images.",
    });
  } catch (e) {
    console.error(e);
    const msg = String(e.message || "");
    if (msg === "Multipart: Unexpected field") {
      res.status(400).json({ error: "Use multipart field name 'file'", max_bytes: UPLOAD_MAX_BYTES });
      return;
    }
    res.status(500).json({ error: "upload_failed", detail: msg });
  }
});

/**
 * Analyze an uploaded medical document (does not persist). Counts AI usage on success only.
 */
app.post("/api/prescriptions/analyze-image", requireUser, upload.single("image"), async (req, res) => {
  try {
    if (!req.file) {
      res.status(400).json({ error: 'multipart field "image" is required' });
      return;
    }
    const mime = req.file.mimetype || "image/jpeg";
    if (!/^image\/(jpeg|png|webp|gif)$/.test(mime)) {
      res.status(400).json({ error: "Unsupported image type (use jpeg, png, webp, or gif)" });
      return;
    }

    await bootstrapUserContext(req.supabase, req.user);
    const peek = await peekAiExtractionsBudget(req.supabase);
    if (
      !peek.unlimited &&
      peek.limit !== null &&
      typeof peek.used === "number" &&
      typeof peek.limit === "number" &&
      peek.used >= peek.limit
    ) {
      return res.status(402).json({
        error: "AI extraction quota exhausted for current billing period.",
        quota: { used: peek.used, monthly_limit: peek.limit, unlimited: peek.unlimited, plan_slug: peek.plan_slug },
      });
    }

    let parsed = await analyzeMedicalDocumentImage(openai, req.file.buffer, mime);

    let documentKind =
      parsed.document_kind === "report" ?
        "report"
      : "prescription";
    parsed = normalizeAnalysisShape(parsed, documentKind);

    const quota = await consumeAiExtraction(req.supabase);
    if (!quota?.allowed) {
      console.error("AI billed but RPC quota rejected unexpectedly", quota);
      return res.status(402).json({
        error: "AI extraction quota exhausted for current billing period.",
        quota,
      });
    }

    res.json({ analysis: parsed, quota });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Analysis failed", detail: String(e.message || e) });
  }
});

function normalizeAnalysisShape(parsedIn, enforcedKind) {
  const cloned = structuredClone(parsedIn);
  cloned.document_kind = enforcedKind;
  if (enforcedKind === "report") {
    cloned.medications = [];
    cloned.report_summary = cloned.report_summary && typeof cloned.report_summary === "object" ? cloned.report_summary : {};
  } else {
    cloned.report_summary =
      cloned.report_summary === undefined || cloned.report_summary === null ? null : cloned.report_summary;
    if (!Array.isArray(cloned.medications)) cloned.medications = [];
  }
  return cloned;
}

/**
 * Analyze base64-encoded image JSON: { "image_base64": "...", "mime_type": "image/jpeg" }
 */
app.post("/api/prescriptions/analyze-image-json", requireUser, async (req, res) => {
  try {
    const { image_base64: b64, mime_type: mimeRaw } = req.body || {};
    if (!b64 || typeof b64 !== "string") {
      res.status(400).json({ error: "image_base64 string required" });
      return;
    }
    const mime = typeof mimeRaw === "string" && mimeRaw ? mimeRaw : "image/jpeg";
    if (!/^image\/(jpeg|png|webp|gif)$/.test(mime)) {
      res.status(400).json({ error: "Unsupported mime_type" });
      return;
    }

    await bootstrapUserContext(req.supabase, req.user);
    const peek = await peekAiExtractionsBudget(req.supabase);
    if (
      !peek.unlimited &&
      peek.limit !== null &&
      typeof peek.used === "number" &&
      typeof peek.limit === "number" &&
      peek.used >= peek.limit
    ) {
      return res.status(402).json({
        error: "AI extraction quota exhausted for current billing period.",
        quota: { used: peek.used, monthly_limit: peek.limit, unlimited: peek.unlimited, plan_slug: peek.plan_slug },
      });
    }

    const buffer = Buffer.from(b64, "base64");
    let parsed = await analyzeMedicalDocumentImage(openai, buffer, mime);
    let documentKind =
      parsed.document_kind === "report" ?
        "report"
      : "prescription";
    parsed = normalizeAnalysisShape(parsed, documentKind);

    const quota = await consumeAiExtraction(req.supabase);
    if (!quota?.allowed) {
      console.error("AI billed but RPC quota rejected unexpectedly", quota);
      return res.status(402).json({
        error: "AI extraction quota exhausted for current billing period.",
        quota,
      });
    }

    res.json({ analysis: parsed, quota });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Analysis failed", detail: String(e.message || e) });
  }
});

function parseDocumentPayload(body = {}) {
  const kindRaw = typeof body.document_kind === "string" ? body.document_kind.toLowerCase() : "prescription";
  const documentKind = kindRaw === "report" ? "report" : "prescription";
  let reportSummary = body.report_summary;
  if (documentKind !== "report") reportSummary = null;
  else if (reportSummary === undefined || reportSummary === null) reportSummary = {};
  else if (typeof reportSummary !== "object") reportSummary = { raw_value: reportSummary };
  return { documentKind, reportSummary };
}

/**
 * Create a prescription/report row (manual or post-analysis).
 * Analyzed uploads: auto-match patient → family_member (exact / fuzzy / random among household),
 * and auto-insert medicine_schedules using prescription_date + per-line duration + inferred times.
 *
 * Body (optional booleans override defaults for `source !== analyzed` callers):
 * - auto_resolve_patient_family_member — default true when source=analyzed
 * - auto_generate_reminders — default true when source=analyzed
 * - patient_family_member_id — explicit link (skips match/random)
 * - default_times — string[] HH:mm for schedule synthesis fallbacks
 */
app.post("/api/prescriptions", requireUser, async (req, res) => {
  try {
    await bootstrapUserContext(req.supabase, req.user);
    const body = req.body || {};
    const source = body.source === "analyzed" ? "analyzed" : "manual";
    const meds = Array.isArray(body.medications) ? body.medications : [];
    const { documentKind, reportSummary } = parseDocumentPayload(body);

    let autoResolve = source === "analyzed";
    if (typeof body.auto_resolve_patient_family_member === "boolean") {
      autoResolve = body.auto_resolve_patient_family_member;
    }

    let autoRemind = source === "analyzed";
    if (typeof body.auto_generate_reminders === "boolean") {
      autoRemind = body.auto_generate_reminders;
    }

    const patientNameStr = typeof body.patient_name === "string" ? body.patient_name : "";

    let explicitFm =
      typeof body.patient_family_member_id === "string" && body.patient_family_member_id.trim().length > 0 ?
        body.patient_family_member_id.trim()
      : null;

    if (explicitFm && !(await validateFamilyOwnership(req.supabase, explicitFm))) {
      return res.status(400).json({ error: "patient_family_member_id must belong to your account." });
    }

    let resolutionSummary =
      explicitFm ?
        { mode: "explicit", family_member_id: explicitFm }
      : { mode: "none", family_member_id: null };

    let linkedFm = explicitFm ?? null;

    if (!linkedFm && autoResolve) {
      const fam = await fetchFamilyMembersForUser(req.supabase, req.user.id);
      const r = resolvePatientFamilyMember(patientNameStr, fam);
      linkedFm = r.family_member_id;
      resolutionSummary = { mode: r.mode, family_member_id: r.family_member_id };
    }

    const rawSourcePath =
      typeof body.source_storage_path === "string" ? body.source_storage_path.trim() : "";
    const normalizedSourcePath = rawSourcePath ? normalizeSourceStoragePath(req.user.id, rawSourcePath) : null;
    if (rawSourcePath && !normalizedSourcePath) {
      return res.status(400).json({ error: "source_storage_path invalid or must match your account prefix." });
    }
    const storedPath = normalizedSourcePath;
    const sourceMime =
      typeof body.source_mime === "string" && body.source_mime.trim().length ? body.source_mime.trim().slice(0, 200) : null;
    const sourceOriginalName =
      typeof body.source_original_name === "string" && body.source_original_name.trim().length ?
        body.source_original_name.trim().slice(0, 500)
      : null;

    const payload = {
      user_id: req.user.id,
      title: typeof body.title === "string" ? body.title : null,
      doctor_name: typeof body.doctor_name === "string" ? body.doctor_name : null,
      patient_name: patientNameStr || null,
      prescription_date: typeof body.prescription_date === "string" ? body.prescription_date : null,
      diagnosis: typeof body.diagnosis === "string" ? body.diagnosis : null,
      general_instructions:
        typeof body.general_instructions === "string" ? body.general_instructions : null,
      medications: documentKind === "prescription" ? meds : [],
      extraction_notes:
        typeof body.extraction_notes === "string" ? body.extraction_notes : null,
      raw_analysis:
        body.raw_analysis !== undefined && body.raw_analysis !== null ? body.raw_analysis : null,
      source,
      document_kind: documentKind,
      report_summary: documentKind === "report" ? reportSummary : null,
      patient_family_member_id: linkedFm,
      source_storage_path: storedPath,
      source_mime: storedPath ? sourceMime || null : null,
      source_original_name: storedPath ? sourceOriginalName || null : null,
    };

    const { data, error } = await req.supabase.from("prescriptions").insert(payload).select("*").single();
    if (error) {
      console.error(error);
      const msg = String(error.message || "");
      if (msg.includes("document_kind")) {
        return res.status(400).json({
          error: error.message,
          hint:
            "Run migration 002_dashboard_feature.sql — document_kind/report_summary columns are required.",
        });
      }
      if (msg.includes("patient_family_member_id")) {
        return res.status(400).json({
          error: error.message,
          hint: "Run migration 003_prescription_patient_member.sql for patient_family_member_id.",
        });
      }
      return res.status(400).json({ error: error.message });
    }

    /** @type {Record<string, any>[]} */
    let schedulesCreated = [];
    /** @type {string | null} */
    let reminderError = null;

    const shouldSynth = autoRemind && documentKind === "prescription" && meds.length > 0;

    if (shouldSynth) {
      try {
        const inserts = buildMedicineScheduleInserts(data, req.user.id, {
          family_member_id: data.patient_family_member_id,
          default_times: Array.isArray(body.default_times) ? body.default_times.map((x) => String(x)) : undefined,
        });
        schedulesCreated = await insertMedicineSchedulesBulk(req.supabase, inserts);
      } catch (e) {
        console.error(e);
        reminderError = String(e.message || e);
      }
    }

    res.status(201).json({
      prescription: data,
      patient_family_resolution: resolutionSummary,
      reminders: {
        generated: schedulesCreated.length,
        schedules: schedulesCreated,
        ...(reminderError ? { error: reminderError } : {}),
      },
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Save failed", detail: String(e.message || e) });
  }
});

app.get("/api/prescriptions", requireUser, async (req, res) => {
  const kind = typeof req.query.kind === "string" ? req.query.kind.toLowerCase().trim() : null;
  let qb = req.supabase.from("prescriptions").select("*");

  if (kind === "prescription" || kind === "report") {
    qb = qb.eq("document_kind", kind);
  }

  const { data, error } = await qb.order("created_at", { ascending: false });

  if (error) return res.status(400).json({ error: error.message });
  res.json({ prescriptions: data || [] });
});

app.get("/api/prescriptions/:id", requireUser, async (req, res) => {
  const { data, error } = await req.supabase.from("prescriptions").select("*").eq("id", req.params.id).maybeSingle();
  if (error) return res.status(400).json({ error: error.message });
  if (!data) return res.status(404).json({ error: "Not found" });
  res.json({ prescription: data });
});

app.patch("/api/prescriptions/:id", requireUser, async (req, res) => {
  const id = req.params.id;
  const { data: existing, error: exErr } = await req.supabase
    .from("prescriptions")
    .select("id,user_id")
    .eq("id", id)
    .maybeSingle();
  if (exErr) return res.status(400).json({ error: exErr.message });
  if (!existing || existing.user_id !== req.user.id) return res.status(404).json({ error: "Not found" });

  const body = req.body || {};
  /** @type {Record<string, any>} */
  const patch = {};

  for (const key of [
    "title",
    "patient_name",
    "doctor_name",
    "prescription_date",
    "diagnosis",
    "general_instructions",
    "extraction_notes",
  ]) {
    if (typeof body[key] === "string") patch[key] = body[key];
    else if (body[key] === null) patch[key] = null;
  }

  if (typeof body.document_kind === "string") {
    const dk = body.document_kind.toLowerCase().trim();
    patch.document_kind = dk === "report" ? "report" : "prescription";
    if (patch.document_kind === "prescription") patch.report_summary = null;
  }

  if (body.report_summary !== undefined) {
    if (body.report_summary === null) patch.report_summary = null;
    else if (typeof body.report_summary === "object") patch.report_summary = body.report_summary;
  }

  if (Array.isArray(body.medications)) {
    patch.medications = body.medications;
  }

  if (body.raw_analysis !== undefined) {
    patch.raw_analysis = body.raw_analysis;
  }

  if (typeof body.source === "string") {
    const s = body.source.toLowerCase().trim();
    if (["manual", "analyzed"].includes(s)) patch.source = s;
  }

  if (body.patient_family_member_id === null) {
    patch.patient_family_member_id = null;
  } else if (typeof body.patient_family_member_id === "string") {
    const fid = body.patient_family_member_id.trim();
    if (fid === "") {
      patch.patient_family_member_id = null;
    } else {
      if (!(await validateFamilyOwnership(req.supabase, fid))) {
        return res.status(400).json({ error: "patient_family_member_id invalid." });
      }
      patch.patient_family_member_id = fid;
    }
  }

  if (Object.prototype.hasOwnProperty.call(body, "source_storage_path")) {
    const raw = typeof body.source_storage_path === "string" ? body.source_storage_path.trim() : "";
    if (!raw) {
      patch.source_storage_path = null;
      patch.source_mime = null;
      patch.source_original_name = null;
    } else {
      const nPath = normalizeSourceStoragePath(req.user.id, raw);
      if (!nPath) return res.status(400).json({ error: "source_storage_path invalid." });
      patch.source_storage_path = nPath;
      if (typeof body.source_mime === "string") patch.source_mime = body.source_mime.trim().slice(0, 200) || null;
      if (typeof body.source_original_name === "string") {
        patch.source_original_name = body.source_original_name.trim().slice(0, 500) || null;
      }
    }
  }

  patch.updated_at = new Date().toISOString();

  const { data, error } = await req.supabase
    .from("prescriptions")
    .update(patch)
    .eq("id", id)
    .eq("user_id", req.user.id)
    .select("*")
    .maybeSingle();
  if (error) return res.status(400).json({ error: error.message });
  if (!data) return res.status(404).json({ error: "Not found" });
  res.json({ prescription: data });
});

app.delete("/api/prescriptions/:id", requireUser, async (req, res) => {
  const id = req.params.id;
  await req.supabase.from("medicine_schedules").delete().eq("prescription_id", id).eq("user_id", req.user.id);
  const { error } = await req.supabase.from("prescriptions").delete().eq("id", id).eq("user_id", req.user.id);
  if (error) return res.status(400).json({ error: error.message });
  res.status(204).end();
});

app.get("/api/family-members", requireUser, async (req, res) => {
  const { data, error } = await req.supabase
    .from("family_members")
    .select("*")
    .eq("owner_user_id", req.user.id)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });
  if (error) return res.status(400).json({ error: error.message });

  await bootstrapUserContext(req.supabase, req.user);
  const { data: chk } = await req.supabase.rpc("can_add_family_member");
  const gate = coerceRpcJson(chk);

  res.json({ members: data || [], quota: gate });
});

app.post("/api/family-members", requireUser, async (req, res) => {
  try {
    await bootstrapUserContext(req.supabase, req.user);
    await assertFamilySeatAvailable(req.supabase);
    const body = req.body || {};
    const displayName =
      typeof body.display_name === "string" ?
        body.display_name.trim()
      : "";
    if (!displayName) return res.status(400).json({ error: "display_name is required" });
    const row = {
      owner_user_id: req.user.id,
      display_name: displayName,
      relation: typeof body.relation === "string" ? body.relation : null,
      birth_year:
        typeof body.birth_year === "number" && Number.isFinite(body.birth_year) ?
          Number(body.birth_year)
        : null,
      notes: typeof body.notes === "string" ? body.notes : null,
      avatar_color: typeof body.avatar_color === "string" ? body.avatar_color : undefined,
      sort_order:
        typeof body.sort_order === "number" && Number.isFinite(body.sort_order) ?
          Number(body.sort_order)
        : 0,
      updated_at: new Date().toISOString(),
    };
    const { data, error } = await req.supabase.from("family_members").insert(row).select("*").single();
    if (error) return res.status(400).json({ error: error.message });
    res.status(201).json({ member: data });
  } catch (e) {
    if (e.code === "member_limit_exceeded") {
      return res.status(402).json({ error: "Family member quota reached.", detail: e.detail });
    }
    console.error(e);
    res.status(500).json({ error: "could_not_create_member", detail: String(e.message || e) });
  }
});

app.patch("/api/family-members/:id", requireUser, async (req, res) => {
  const body = req.body || {};
  /** @type {Record<string, any>} */
  const patch = { updated_at: new Date().toISOString() };

  if (typeof body.display_name === "string") {
    patch.display_name = body.display_name.trim();
  }
  if ("relation" in body) {
    if (body.relation === null) patch.relation = null;
    else if (typeof body.relation === "string") patch.relation = body.relation.trim() || null;
  }
  if ("birth_year" in body) {
    if (body.birth_year === null) patch.birth_year = null;
    else if (typeof body.birth_year === "number" && Number.isFinite(body.birth_year)) {
      patch.birth_year = Number(body.birth_year);
    }
  }
  if ("notes" in body) {
    if (body.notes === null) patch.notes = null;
    else if (typeof body.notes === "string") patch.notes = body.notes.trim() || null;
  }
  if (typeof body.avatar_color === "string") patch.avatar_color = body.avatar_color;
  if (typeof body.sort_order === "number" && Number.isFinite(body.sort_order)) {
    patch.sort_order = Number(body.sort_order);
  }

  const { data, error } = await req.supabase
    .from("family_members")
    .update(patch)
    .eq("id", req.params.id)
    .eq("owner_user_id", req.user.id)
    .select("*")
    .maybeSingle();
  if (error) return res.status(400).json({ error: error.message });
  if (!data) return res.status(404).json({ error: "Not found" });
  res.json({ member: data });
});

app.delete("/api/family-members/:id", requireUser, async (req, res) => {
  const { error } = await req.supabase
    .from("family_members")
    .delete()
    .eq("id", req.params.id)
    .eq("owner_user_id", req.user.id);
  if (error) return res.status(400).json({ error: error.message });
  res.status(204).end();
});

app.get("/api/medicine-schedules", requireUser, async (req, res) => {
  const { data, error } = await req.supabase.from("medicine_schedules").select("*").order("created_at", {
    ascending: false,
  });
  if (error) return res.status(400).json({ error: error.message });
  res.json({ schedules: data || [] });
});

app.get("/api/medicine-schedules/upcoming", requireUser, async (req, res) => {
  const horizon = Number(req.query.days ?? req.query.horizon ?? 3);
  const safeHorizon =
    Number.isFinite(horizon) ?
      Math.min(Math.max(Math.trunc(horizon), 1), 31)
    : 3;

  const { data, error } = await req.supabase.from("medicine_schedules").select("*");

  if (error) return res.status(400).json({ error: error.message });

  const upcoming =
    flattenUpcomingFromRows(data || [], {
      fromUtc: Date.now(),
      horizonDays: safeHorizon,
    }) ?? [];

  res.json({
    horizon_days: safeHorizon,
    occurrences: upcoming,
  });
});

app.post("/api/medicine-schedules", requireUser, async (req, res) => {
  try {
    await bootstrapUserContext(req.supabase, req.user);
    const body = req.body || {};
    const fmId = typeof body.family_member_id === "string" ? body.family_member_id : null;

    if (fmId && !(await validateFamilyOwnership(req.supabase, fmId))) {
      return res.status(400).json({ error: "family_member_id not found under this account." });
    }

    const medsName =
      typeof body.medication_name === "string" ?
        body.medication_name.trim()
      : "";

    const timesCandidate = body.time_points ?? body.times;
    let timePoints =
      Array.isArray(timesCandidate) ? timesCandidate
      : typeof timesCandidate === "string" ?
        JSON.parse(timesCandidate || "[]")
      : [];

    if (!Array.isArray(timePoints) || timePoints.length === 0) {
      timePoints = ["09:00"];
    }

    const start_date =
      typeof body.start_date === "string" && body.start_date.trim().length ?
        body.start_date.trim()
      : new Date().toISOString().slice(0, 10);

    let end_date =
      typeof body.end_date === "string" && body.end_date.trim().length ? body.end_date.trim() : null;

    if (
      end_date === null &&
      typeof body.course_days === "number" &&
      Number.isFinite(body.course_days)
    ) {
      const n = Math.trunc(body.course_days);
      if (n > 0) {
        const computed = addDaysToIso(start_date, n - 1);
        if (computed) end_date = computed;
      }
    }

    const row = {
      user_id: req.user.id,
      family_member_id: fmId,
      source:
        typeof body.source === "string" && ["manual", "prescription_generated"].includes(body.source) ?
          body.source
        : "manual",
      prescription_id: typeof body.prescription_id === "string" ? body.prescription_id : null,
      medication_line_index:
        typeof body.medication_line_index === "number" ? body.medication_line_index : null,
      medication_name: medsName,
      dosage_text: typeof body.dosage_text === "string" ? body.dosage_text : null,
      meal_instruction: typeof body.meal_instruction === "string" ? body.meal_instruction : null,
      schedule_kind:
        typeof body.schedule_kind === "string" && ["daily", "weekly", "one_off"].includes(body.schedule_kind) ?
          body.schedule_kind
        : "daily",
      time_points: timePoints.map((x) => String(x)),
      weekdays:
        typeof body.weekdays === "undefined" || body.weekdays === null ?
          null
        : body.weekdays,
      start_date,
      end_date,
      timezone: typeof body.timezone === "string" ? body.timezone : "UTC",
      updated_at: new Date().toISOString(),
    };

    if (!row.medication_name) {
      return res.status(400).json({ error: "medication_name is required" });
    }

    const { data, error } = await req.supabase.from("medicine_schedules").insert(row).select("*").single();
    if (error) return res.status(400).json({ error: error.message });
    res.status(201).json({ schedule: data });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.patch("/api/medicine-schedules/:id", requireUser, async (req, res) => {
  const body = req.body || {};

  /** @type {Record<string, any>} */
  const patch = {};

  ["medication_name", "timezone", "start_date", "prescription_id"].forEach((k) => {
    if (typeof body[k] === "string") patch[k] = body[k];
  });

  if ("dosage_text" in body) {
    if (typeof body.dosage_text === "string") {
      patch.dosage_text = body.dosage_text.trim().length ? body.dosage_text.trim() : null;
    } else {
      patch.dosage_text = null;
    }
  }
  if ("meal_instruction" in body) {
    if (typeof body.meal_instruction === "string") {
      patch.meal_instruction = body.meal_instruction.trim().length ? body.meal_instruction.trim() : null;
    } else {
      patch.meal_instruction = null;
    }
  }

  if ("end_date" in body) {
    if (typeof body.end_date === "string" && body.end_date.trim().length > 0) {
      patch.end_date = body.end_date.trim();
    } else {
      patch.end_date = null;
    }
  }
  if (typeof body.medication_line_index === "number") patch.medication_line_index = body.medication_line_index;
  if (typeof body.family_member_id === "string" || body.family_member_id === null) {
    if (typeof body.family_member_id === "string") {
      if (!(await validateFamilyOwnership(req.supabase, body.family_member_id))) {
        return res.status(400).json({ error: "family_member_id invalid" });
      }
    }
    patch.family_member_id = body.family_member_id;
  }
  if (
    typeof body.schedule_kind === "string" &&
    ["daily", "weekly", "one_off"].includes(body.schedule_kind)
  ) {
    patch.schedule_kind = body.schedule_kind;
  }

  const timesCandidate = body.time_points ?? body.times;
  if (Array.isArray(timesCandidate)) {
    patch.time_points = timesCandidate.map((x) => String(x));
  }
  if (body.weekdays !== undefined) patch.weekdays = body.weekdays;

  patch.updated_at = new Date().toISOString();

  const { data, error } = await req.supabase
    .from("medicine_schedules")
    .update(patch)
    .eq("id", req.params.id)
    .eq("user_id", req.user.id)
    .select("*")
    .maybeSingle();
  if (error) return res.status(400).json({ error: error.message });
  if (!data) return res.status(404).json({ error: "Not found" });
  res.json({ schedule: data });
});

app.delete("/api/medicine-schedules/:id", requireUser, async (req, res) => {
  const { error } = await req.supabase.from("medicine_schedules").delete().eq("id", req.params.id).eq(
    "user_id",
    req.user.id,
  );
  if (error) return res.status(400).json({ error: error.message });
  res.status(204).end();
});

async function hydratePrescription(supabase, id) {
  const { data, error } = await supabase.from("prescriptions").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  return data;
}

app.post("/api/medicine-schedules/from-prescription", requireUser, async (req, res) => {
  try {
    await bootstrapUserContext(req.supabase, req.user);
    const body = req.body || {};
    const pid =
      typeof body.prescription_id === "string" && body.prescription_id.trim().length > 0 ?
        body.prescription_id.trim()
      : null;

    if (!pid) {
      return res.status(400).json({ error: "prescription_id is required" });
    }

    const rx = await hydratePrescription(req.supabase, pid);
    if (!rx) return res.status(404).json({ error: "prescription_not_found" });
    if ((rx.document_kind || "prescription") !== "prescription") {
      return res.status(400).json({ error: "Selected record is flagged as report; schedules require prescriptions." });
    }

    let fmId =
      typeof body.family_member_id === "string" && body.family_member_id.length ?
        body.family_member_id
      : null;
    if (!fmId && rx.patient_family_member_id) {
      fmId = rx.patient_family_member_id;
    }
    if (fmId && !(await validateFamilyOwnership(req.supabase, fmId))) {
      return res.status(400).json({ error: "family_member_id invalid" });
    }

    const defaultTimes = Array.isArray(body.default_times) ? body.default_times.map((x) => String(x)) : ["09:00"];

    const inserts = buildMedicineScheduleInserts(rx, req.user.id, {
      family_member_id: fmId,
      default_times: defaultTimes,
      start_date: typeof body.start_date === "string" ? body.start_date : undefined,
    });

    if (!inserts.length) {
      return res.status(201).json({
        schedules: [],
        prescription_id: pid,
        synthesized: 0,
      });
    }

    const created = await insertMedicineSchedulesBulk(req.supabase, inserts);

    res.status(201).json({
      schedules: created,
      prescription_id: pid,
      synthesized: created.length,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.listen(PORT, () => {
  console.log(`MediBuddy API listening on http://localhost:${PORT}`);
});
