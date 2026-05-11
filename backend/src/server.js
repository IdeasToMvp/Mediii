import "dotenv/config";
import cors from "cors";
import express from "express";
import multer from "multer";
import { createClient } from "@supabase/supabase-js";
import { createHash, randomUUID, timingSafeEqual } from "crypto";
import path from "path";
import OpenAI from "openai";
import { analyzeMedicalDocumentImage } from "./openaiMedicalDocument.js";
import { flattenUpcomingFromRows } from "./medicineExpansion.js";
import { buildMedicineScheduleInserts, addDaysToIso } from "./medicineSynth.js";
import { resolvePatientFamilyMember } from "./patientFamilyResolve.js";
import {
  applySubscriptionToEntitlements,
  createRazorpayCustomerOrReuse,
  describeRazorpayThrown,
  getRazorpay,
  getRazorpayPlanId,
  getSupabaseAdmin,
  handleRazorpayWebhook,
  normalizeBillingInterval,
} from "./razorpayBilling.js";

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

/** Must stay ≤ Supabase bucket `file_size_limit` for `app-distributions` (see migrations 011 / 012). */
const APK_UPLOAD_MAX_BYTES = 500 * 1024 * 1024;

const uploadApk = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: APK_UPLOAD_MAX_BYTES },
});

const app = express();
app.use(cors());

/** Razorpay must verify HMAC against the raw request body (before express.json). */
app.post("/api/billing/razorpay/webhook", express.raw({ type: "application/json", limit: "2mb" }), handleRazorpayWebhook);

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
  const paid = planSlug === "pro";
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

    let { data: ue } = await req.supabase.from("user_entitlements").select("*").maybeSingle();

    let planMeta = null;
    if (ue?.plan_slug) {
      const { data: pm } = await req.supabase.from("subscription_plans").select("*").eq("slug", ue.plan_slug).maybeSingle();
      planMeta = pm;
    }

    const { monthly_ai_extractions: _aiCapInternal, ...planRest } = planMeta && typeof planMeta === "object" ? planMeta : {};

    const { count: fmCount /* family members */ } = await req.supabase
      .from("family_members")
      .select("id", { count: "exact", head: true });

    const entitlementPublic =
      ue && typeof ue === "object" ?
        (() => {
          const { ai_extractions_used: _usage, ...rest } = ue;
          return rest;
        })()
      : null;

    res.json({
      user: {
        id: req.user.id,
        email: req.user.email,
      },
      profile: profile ?? null,
      entitlement: entitlementPublic,
      plan:
        planMeta ?
          {
            ...planRest,
            pro_access_until: ue?.razorpay_pro_access_until ?? null,
            family_slots_used: fmCount ?? 0,
            upload_caps: {
              max_bytes: UPLOAD_MAX_BYTES,
              allows_multi_pick: ue?.plan_slug === "pro",
              allows_pdf: ue?.plan_slug === "pro",
              image_types: "JPEG, PNG, WebP, GIF",
              paid_label: "Pro",
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

/** Public key + defaults for Razorpay Checkout (subscriptions). */
app.get("/api/billing/razorpay/config", requireUser, (req, res) => {
  const keyId = process.env.RAZORPAY_KEY_ID?.trim();
  if (!keyId) {
    res.status(503).json({ error: "Razorpay is not configured (RAZORPAY_KEY_ID)" });
    return;
  }
  const currency = process.env.RAZORPAY_CURRENCY?.trim() || "INR";
  res.json({ key_id: keyId, currency });
});

/**
 * Creates a Razorpay customer (stored on entitlements) and subscription with notes for webhooks.
 * Client opens Checkout with `key_id` + `subscription_id`.
 */
app.post("/api/billing/razorpay/create-subscription", requireUser, async (req, res) => {
  try {
    const rzp = getRazorpay();
    const admin = getSupabaseAdmin();
    if (!rzp) {
      res.status(503).json({ error: "Razorpay is not configured (RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET)" });
      return;
    }
    if (!admin) {
      res.status(503).json({
        error:
          "Server billing requires SUPABASE_SERVICE_ROLE_KEY (store Razorpay customer id + process webhooks)",
      });
      return;
    }

    await bootstrapUserContext(req.supabase, req.user);

    const planSlug = String(req.body?.plan_slug || "")
      .trim()
      .toLowerCase();
    if (planSlug !== "pro") {
      res.status(400).json({ error: "plan_slug must be pro" });
      return;
    }

    const billingInterval = normalizeBillingInterval(req.body?.billing_interval);

    const planId = getRazorpayPlanId(planSlug, billingInterval);
    if (!planId) {
      res.status(503).json({
        error:
          billingInterval === "annual" ?
            "Annual Pro plan id missing — set RAZORPAY_PLAN_ID_PRO_ANNUAL in environment"
          : "Monthly Pro plan id missing — set RAZORPAY_PLAN_ID_PRO_MONTHLY (or legacy RAZORPAY_PLAN_ID_PRO) in environment",
      });
      return;
    }

    const { data: ent } = await req.supabase.from("user_entitlements").select("*").maybeSingle();
    const { data: prof } = await req.supabase.from("user_profiles").select("display_name").maybeSingle();

    const customerNotify = req.body?.customer_notify !== false;

    let customerId = typeof ent?.razorpay_customer_id === "string" ? ent.razorpay_customer_id.trim() : "";
    if (!customerId) {
      const displayName =
        typeof prof?.display_name === "string" && prof.display_name.trim() ?
          prof.display_name.trim()
        : inferDisplayName(req.user);
      const email = typeof req.user.email === "string" ? req.user.email.trim() : "";

      const customerIdResolved = await createRazorpayCustomerOrReuse(rzp, {
        name: displayName,
        email,
        supabaseUserId: req.user.id,
      });
      customerId = customerIdResolved;

      const { error: custErr } = await admin
        .from("user_entitlements")
        .update({ razorpay_customer_id: customerId, updated_at: new Date().toISOString() })
        .eq("user_id", req.user.id);
      if (custErr) {
        console.error(custErr);
        throw new Error(custErr.message);
      }
    }

    const totalCount = Number.parseInt(process.env.RAZORPAY_SUBSCRIPTION_TOTAL_COUNT || "120", 10);

    const sub = await rzp.subscriptions.create({
      plan_id: planId,
      customer_id: customerId,
      total_count: Number.isFinite(totalCount) && totalCount > 0 ? totalCount : 120,
      customer_notify: customerNotify ? 1 : 0,
      notes: {
        supabase_user_id: String(req.user.id),
        plan_slug: String(planSlug),
        billing_interval: String(billingInterval),
      },
    });

    res.json({
      key_id: process.env.RAZORPAY_KEY_ID,
      subscription_id: sub.id,
      short_url: sub.short_url || null,
      status: sub.status,
    });
  } catch (e) {
    const d = describeRazorpayThrown(e);
    console.error("create-subscription failed", d.kind, d.description, d.raw);
    if (d.kind === "razorpay") {
      res.status(502).json({
        error: "razorpay_error",
        detail: d.description,
        code: d.code,
        source: d.source,
        statusCode: d.statusCode,
      });
      return;
    }
    res.status(500).json({ error: d.description || "create_subscription_failed" });
  }
});

/**
 * Pull subscription from Razorpay and apply to entitlements. Call after Checkout success when webhooks lag (local dev or cold start).
 */
app.post("/api/billing/razorpay/sync-subscription", requireUser, async (req, res) => {
  try {
    const rzp = getRazorpay();
    if (!rzp) {
      res.status(503).json({ error: "Razorpay is not configured" });
      return;
    }

    const subId = String(req.body?.subscription_id || "").trim();
    if (!subId.startsWith("sub_")) {
      res.status(400).json({ error: "subscription_id must be a Razorpay subscription id (sub_…)" });
      return;
    }

    let entity;
    try {
      entity = await rzp.subscriptions.fetch(subId);
    } catch (e) {
      const d = describeRazorpayThrown(e);
      res.status(502).json({ error: "razorpay_error", detail: d.description });
      return;
    }

    const notes = entity?.notes && typeof entity.notes === "object" ? entity.notes : {};
    const noteUid = typeof notes.supabase_user_id === "string" ? notes.supabase_user_id.trim() : "";
    if (!noteUid || noteUid !== req.user.id) {
      res.status(403).json({ error: "Subscription does not belong to this account." });
      return;
    }

    const result = await applySubscriptionToEntitlements(entity);
    res.json({ ok: true, result });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message || String(e) });
  }
});

/**
 * Persist original bytes to private storage ({user_id}/{uuid}.ext).
 * Free: images only (jpeg, png, webp, gif). Pro: also application/pdf.
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
            "Free plan accepts JPEG/PNG/WebP/GIF only. Pro can also upload PDFs."
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
        : "Pro: multi-select images · PDF uploads · images + PDF · max 10 MB per file. AI analyzes photo images.",
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

const APP_RELEASES_PUBLIC_FIELDS =
  "id, platform, version_label, version_code, channel, release_notes, apk_filename, apk_byte_size, apk_sha256_hex, created_at, apk_download_url, update_mandatory";

/**
 * multipart / JSON: update_mandatory true | false | "1" | "0"
 * @param {unknown} raw
 */
function parseUpdateMandatory(raw) {
  if (raw === undefined || raw === null) return false;
  if (typeof raw === "boolean") return raw;
  const s = String(raw).trim().toLowerCase();
  return s === "1" || s === "true" || s === "yes" || s === "on";
}

/**
 * Prefer Google Drive `uc?export=download` URLs; keep other https links as-is (trim + strip hash).
 */
function normalizeHostedDistributionUrl(raw) {
  const s = String(raw || "").trim();
  if (!s) return null;
  let u;
  try {
    u = new URL(s);
  } catch {
    return null;
  }
  if (u.protocol !== "https:") {
    return null;
  }
  const host = u.hostname.toLowerCase();
  if (host === "drive.google.com") {
    let id = u.searchParams.get("id");
    const mPath = u.pathname.match(/\/(?:file\/)?d\/([a-zA-Z0-9_-]+)/);
    if (!id && mPath) id = mPath[1];
    if (id && /^[a-zA-Z0-9_-]+$/.test(id)) {
      return `https://drive.google.com/uc?export=download&id=${id}`;
    }
  }
  if (host === "docs.google.com" && u.pathname.startsWith("/uc")) {
    return u.toString().split("#")[0];
  }
  return u.toString().split("#")[0];
}

function parseReleaseChannel(raw) {
  const s = String(raw || "production").trim().toLowerCase();
  if (s === "beta" || s === "internal") return s;
  return "production";
}

/** @param {unknown} body */
function platformFromBody(body) {
  const o = body && typeof body === "object" ? body : {};
  const alias = /** @type {Record<string, unknown>} */ (o).build_type ?? /** @type {Record<string, unknown>} */ (o).platform;
  const raw = alias !== undefined && alias !== null ? String(alias).trim().toLowerCase() : "";
  return parseBuildPlatform(raw || "android");
}

function parseBuildPlatform(raw) {
  const s = String(raw ?? "android").trim().toLowerCase();
  if (s === "ios") return "ios";
  return "android";
}

function getReleaseUploadSecret() {
  const a = process.env.APK_ADMIN_UPLOAD_TOKEN?.trim();
  const b = process.env.UPLOAD_RELEASE_API_KEY?.trim();
  return a || b || "";
}

/** @returns {string} */
function headerString(req, name) {
  const v = req.headers[name];
  const s = Array.isArray(v) ? v[0] : v;
  return String(s ?? "").trim();
}

/** @returns {string} */
function extractProvidedUploadCredential(req) {
  const bearer = headerString(req, "authorization");
  if (/^Bearer\s+/i.test(bearer)) {
    const t = bearer.replace(/^Bearer\s+/i, "").trim();
    if (t) return t;
  }
  let v = headerString(req, "x-upload-api-key");
  if (v) return v;
  v =
    headerString(req, "x-admin-upload-token") ||
    headerString(req, "x-apk-admin-token");
  return v || "";
}

function requireApkAdminUploadToken(req, res, next) {
  const expected = getReleaseUploadSecret();
  if (!expected) {
    res.status(503).json({
      error: "apk_admin_disabled",
      detail:
        "Set APK_ADMIN_UPLOAD_TOKEN or UPLOAD_RELEASE_API_KEY to enable release uploads (/api/admin/app-releases …).",
    });
    return;
  }
  const a = extractProvidedUploadCredential(req);
  const b = expected;
  if (!a || a.length !== b.length) {
    res.status(401).json({
      error: "missing_or_invalid_upload_key",
      detail:
        "Send a mandatory upload credential: header X-Upload-Api-Key, or Authorization: Bearer <token>, or X-Admin-Upload-Token matching the server secret.",
    });
    return;
  }
  try {
    if (!timingSafeEqual(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"))) {
      res.status(401).json({ error: "missing_or_invalid_upload_key" });
      return;
    }
  } catch {
    res.status(401).json({ error: "missing_or_invalid_upload_key" });
    return;
  }
  next();
}

/** Latest Android build metadata (public; download via signed Storage URL or apk_download_url). */
app.get("/api/app-releases/latest", async (req, res) => {
  try {
    const admin = getSupabaseAdmin();
    if (!admin) {
      res.status(503).json({ error: "server_misconfigured", detail: "SUPABASE_SERVICE_ROLE_KEY is required" });
      return;
    }
    const channel = parseReleaseChannel(req.query.channel);
    const platform = parseBuildPlatform(req.query.platform);
    const { data, error } = await admin
      .from("app_releases")
      .select(APP_RELEASES_PUBLIC_FIELDS)
      .eq("channel", channel)
      .eq("platform", platform)
      .order("version_code", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error(error);
      res.status(500).json({ error: "release_query_failed", detail: error.message });
      return;
    }
    if (!data) {
      res.status(404).json({
        error: "no_release",
        detail: `No ${platform.toUpperCase()} build published for channel '${channel}' yet.`,
      });
      return;
    }

    res.json({ release: data });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "release_load_failed", detail: String(e.message || e) });
  }
});

/** Short-lived signed URL to download the APK (public). */
app.get("/api/app-releases/:id/download-url", async (req, res) => {
  try {
    const admin = getSupabaseAdmin();
    if (!admin) {
      res.status(503).json({ error: "server_misconfigured", detail: "SUPABASE_SERVICE_ROLE_KEY is required" });
      return;
    }

    const id = String(req.params.id || "").trim();
    if (!id) {
      res.status(400).json({ error: "missing_id" });
      return;
    }

    const { data: row, error: fetchErr } = await admin.from("app_releases").select("*").eq("id", id).maybeSingle();
    if (fetchErr) {
      console.error(fetchErr);
      res.status(500).json({ error: "release_query_failed", detail: fetchErr.message });
      return;
    }
    if (!row) {
      res.status(404).json({ error: "release_not_found" });
      return;
    }

    const ttlRaw = Number.parseInt(process.env.APK_DOWNLOAD_URL_TTL_SEC || "3600", 10);
    const ttl = Math.min(Math.max(Number.isFinite(ttlRaw) ? ttlRaw : 3600, 60), 60 * 60 * 24 * 7);

    if (typeof row.apk_download_url === "string" && row.apk_download_url.trim()) {
      const dl = normalizeHostedDistributionUrl(row.apk_download_url) || row.apk_download_url.trim();
      /** @type {Record<string, any>} */
      const pub = {};
      for (const k of APP_RELEASES_PUBLIC_FIELDS.split(/\s*,\s*/)) {
        if (row[k] !== undefined) pub[k] = row[k];
      }
      res.json({
        download_url: dl,
        expires_in_seconds: null,
        filename: row.apk_filename,
        release: pub,
      });
      return;
    }

    if (!row.apk_storage_path) {
      res.status(500).json({ error: "release_has_no_download", detail: "No storage path or external URL configured." });
      return;
    }

    const { data: signed, error: signErr } = await admin.storage.from("app-distributions").createSignedUrl(row.apk_storage_path, ttl, {
      download: row.apk_filename || "MediSathi.apk",
    });

    if (signErr || !signed?.signedUrl) {
      console.error(signErr);
      res.status(500).json({ error: "signed_url_failed", detail: signErr?.message || "unknown" });
      return;
    }

    /** @type {Record<string, any>} */
    const pub = {};
    for (const k of APP_RELEASES_PUBLIC_FIELDS.split(/\s*,\s*/)) {
      if (row[k] !== undefined) pub[k] = row[k];
    }

    res.json({
      download_url: signed.signedUrl,
      expires_in_seconds: ttl,
      filename: row.apk_filename,
      release: pub,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "download_url_failed", detail: String(e.message || e) });
  }
});

/**
 * Publish a new APK (manual / Postman). Auth: header X-Admin-Upload-Token (see APK_ADMIN_UPLOAD_TOKEN).
 * Multipart fields: apk (file), version, version_code, release_notes?, channel?, update_mandatory?, platform? / build_type? (android|ios)
 */
app.post("/api/admin/app-releases", requireApkAdminUploadToken, uploadApk.single("apk"), async (req, res) => {
  try {
    if (!req.file) {
      res.status(400).json({
        error: "missing_apk",
        detail: 'Multipart field "apk" (artifact file). Max size 500 MB. Optional text fields: platform or build_type (android|ios).',
        max_bytes: APK_UPLOAD_MAX_BYTES,
      });
      return;
    }

    const admin = getSupabaseAdmin();
    if (!admin) {
      res.status(503).json({ error: "server_misconfigured", detail: "SUPABASE_SERVICE_ROLE_KEY is required" });
      return;
    }

    const versionLabel = String(req.body?.version || req.body?.version_label || "").trim();
    if (!versionLabel || versionLabel.length > 80) {
      res.status(400).json({
        error: "invalid_version",
        detail: 'Form field "version" is required (e.g. 1.4.2), max 80 characters.',
      });
      return;
    }

    let versionCode = Number.parseInt(String(req.body?.version_code ?? ""), 10);
    if (!Number.isFinite(versionCode)) {
      res.status(400).json({
        error: "invalid_version_code",
        detail: 'Form field "version_code" must be an integer (Android versionCode from build.gradle).',
      });
      return;
    }
    versionCode = Math.trunc(versionCode);
    if (versionCode < 1 || versionCode > 2147483647) {
      res.status(400).json({ error: "invalid_version_code", detail: "version_code must be between 1 and 2^31-1" });
      return;
    }

    const channel = parseReleaseChannel(req.body?.channel);
    const platform = platformFromBody(req.body);
    const notes = typeof req.body?.release_notes === "string" ? req.body.release_notes.trim().slice(0, 32000) : "";
    const updateMandatory = parseUpdateMandatory(req.body?.update_mandatory);

    let origDefault = platform === "ios" ? "medisathi-release.ipa" : "medisathi-release.apk";
    let orig =
      typeof req.file.originalname === "string" && req.file.originalname.trim() ?
        req.file.originalname.trim().slice(0, 240)
      : origDefault;

    const wantExt = platform === "ios" ? ".ipa" : ".apk";
    if (!orig.toLowerCase().endsWith(wantExt)) {
      orig = `${orig.replace(/\.+$/g, "")}${wantExt}`;
    }

    const mime = (req.file.mimetype || "").toLowerCase();
    /** @type {boolean} */
    const mimeOk =
      platform === "ios" ?
        mime === "" ||
        mime === "application/octet-stream" ||
        mime === "application/zip" ||
        mime === "application/x-itunes-ipa" ||
        mime === "application/x-zip-compressed"
      : mime === "" ||
        mime === "application/octet-stream" ||
        mime === "application/vnd.android.package-archive" ||
        mime === "application/apk";

    if (!mimeOk) {
      res.status(400).json({
        error: "invalid_artifact_mime",
        detail:
          platform === "ios" ?
            "For iOS uploads use application/octet-stream / zip (IPA), or omit Content-Type."
          : "For Android use application/vnd.android.package-archive or application/octet-stream.",
        received_mime: mime,
        platform,
      });
      return;
    }

    const sha256 = createHash("sha256").update(req.file.buffer).digest("hex");
    const id = randomUUID();
    const artifactExt = platform === "ios" ? "ipa" : "apk";
    const objectPath = `releases/${id}.${artifactExt}`;

    const storageContentType =
      platform === "ios" ? "application/octet-stream" : "application/vnd.android.package-archive";

    const { error: upErr } = await admin.storage.from("app-distributions").upload(objectPath, req.file.buffer, {
      contentType: storageContentType,
      upsert: false,
    });

    if (upErr) {
      console.error(upErr);
      res.status(500).json({ error: "storage_upload_failed", detail: upErr.message });
      return;
    }

    const row = {
      id,
      platform,
      version_label: versionLabel,
      version_code: versionCode,
      channel,
      release_notes: notes,
      update_mandatory: updateMandatory,
      apk_storage_path: objectPath,
      apk_download_url: null,
      apk_filename: orig,
      apk_byte_size: req.file.size,
      apk_sha256_hex: sha256,
    };

    const { data: inserted, error: insErr } = await admin.from("app_releases").insert(row).select(APP_RELEASES_PUBLIC_FIELDS).single();

    if (insErr) {
      console.error(insErr);
      await admin.storage.from("app-distributions").remove([objectPath]).catch(() => {});
      res.status(500).json({ error: "release_insert_failed", detail: insErr.message });
      return;
    }

    res.status(201).json({
      release: inserted,
      download_example: `GET ${req.protocol}://${req.get("host")}/api/app-releases/${id}/download-url`,
    });
  } catch (e) {
    console.error(e);
    const msg = String(e.message || "");
    if (msg === "Multipart: Unexpected field") {
      res.status(400).json({
        error: "unexpected_multipart_field",
        detail: "Use multipart field name 'apk' for the file",
        max_bytes: APK_UPLOAD_MAX_BYTES,
      });
      return;
    }
    res.status(500).json({ error: "apk_upload_failed", detail: msg });
  }
});

/**
 * Register a release with an externally hosted artifact (HTTPS), e.g. Google Drive link to APK or IPA.
 * Body JSON: download_url, version, version_code, platform?, build_type?, release_notes?, channel?, update_mandatory?, apk_filename?, apk_byte_size?
 */
app.post("/api/admin/app-releases/link", requireApkAdminUploadToken, async (req, res) => {
  try {
    const admin = getSupabaseAdmin();
    if (!admin) {
      res.status(503).json({ error: "server_misconfigured", detail: "SUPABASE_SERVICE_ROLE_KEY is required" });
      return;
    }

    const rawLink = typeof req.body?.download_url === "string" ? req.body.download_url.trim() : "";
    if (!rawLink) {
      res.status(400).json({
        error: "missing_download_url",
        detail: 'JSON body field "download_url" is required (Google Drive sharing link or other https APK URL).',
      });
      return;
    }

    const naked = rawLink.split("#")[0].trim();

    const normalized = normalizeHostedDistributionUrl(naked);
    const canonical = normalized || naked;
    if (!canonical.startsWith("https://")) {
      res.status(400).json({
        error: "invalid_download_url",
        detail: "Only HTTPS download URLs are accepted.",
      });
      return;
    }

    const versionLabel = String(req.body?.version || req.body?.version_label || "").trim();
    if (!versionLabel || versionLabel.length > 80) {
      res.status(400).json({
        error: "invalid_version",
        detail: '"version" is required (e.g. 1.4.2), max 80 characters.',
      });
      return;
    }

    let versionCode = Number.parseInt(String(req.body?.version_code ?? ""), 10);
    if (!Number.isFinite(versionCode)) {
      res.status(400).json({
        error: "invalid_version_code",
        detail: '"version_code" must be an integer matching Android versionCode.',
      });
      return;
    }
    versionCode = Math.trunc(versionCode);
    if (versionCode < 1 || versionCode > 2147483647) {
      res.status(400).json({ error: "invalid_version_code" });
      return;
    }

    const channel = parseReleaseChannel(req.body?.channel);
    const platform = platformFromBody(req.body);
    const notes = typeof req.body?.release_notes === "string" ? req.body.release_notes.trim().slice(0, 32000) : "";
    const updateMandatory = parseUpdateMandatory(req.body?.update_mandatory);

    const defaultFn = platform === "ios" ? "MediSathi.ipa" : "MediSathi.apk";
    const wantExt = platform === "ios" ? ".ipa" : ".apk";
    let filename =
      typeof req.body?.apk_filename === "string" && req.body.apk_filename.trim().length ?
        req.body.apk_filename.trim().slice(0, 240)
      : defaultFn;
    if (!filename.toLowerCase().endsWith(wantExt)) {
      filename = `${filename.replace(/\.+$/g, "")}${wantExt}`;
    }

    let byteSize = null;
    const rawSz = req.body?.apk_byte_size;
    if (rawSz !== undefined && rawSz !== null && String(rawSz).trim() !== "") {
      const n = Number(rawSz);
      if (Number.isFinite(n) && n > 0 && n <= 20 * 1024 * 1024 * 1024) byteSize = Math.trunc(n);
    }

    const id = randomUUID();
    const row = {
      id,
      platform,
      version_label: versionLabel,
      version_code: versionCode,
      channel,
      release_notes: notes,
      update_mandatory: updateMandatory,
      apk_storage_path: null,
      apk_download_url: canonical,
      apk_filename: filename,
      apk_byte_size: byteSize,
      apk_sha256_hex: null,
    };

    const { data: inserted, error: insErr } = await admin.from("app_releases").insert(row).select(APP_RELEASES_PUBLIC_FIELDS).single();

    if (insErr) {
      console.error(insErr);
      res.status(500).json({ error: "release_insert_failed", detail: insErr.message });
      return;
    }

    res.status(201).json({
      release: inserted,
      resolved_download_url: inserted?.apk_download_url,
      hint: `GET ${req.protocol}://${req.get("host")}/api/app-releases/${id}/download-url returns JSON with download_url.`,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "link_release_failed", detail: String(e.message || e) });
  }
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
