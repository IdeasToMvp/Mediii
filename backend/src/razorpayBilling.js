import crypto from "crypto";
import Razorpay from "razorpay";
import { createClient } from "@supabase/supabase-js";

/**
 * @returns {import("@supabase/supabase-js").SupabaseClient | null}
 */
export function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/**
 * @returns {Razorpay | null}
 */
export function getRazorpay() {
  const id = process.env.RAZORPAY_KEY_ID;
  const secret = process.env.RAZORPAY_KEY_SECRET;
  if (!id || !secret) return null;
  return new Razorpay({ key_id: id, key_secret: secret });
}

/**
 * @param {string} [billingInterval] monthly | annual (also accepts month, yearly, year)
 */
export function normalizeBillingInterval(raw) {
  const s = String(raw ?? "monthly")
    .trim()
    .toLowerCase();
  if (s === "year" || s === "yearly" || s === "annual") return "annual";
  return "monthly";
}

/**
 * Razorpay has one plan_id per price + billing frequency. Use MONTHLY and ANNUAL env vars.
 * Legacy: RAZORPAY_PLAN_ID_PRO alone is treated as the monthly plan id if MONTHLY is unset.
 *
 * @param {string} [billingInterval] normalized externally or passed raw
 */
export function getRazorpayPlanId(planSlug, billingInterval = "monthly") {
  const s = String(planSlug || "")
    .trim()
    .toLowerCase();
  if (s !== "pro") return null;

  const bi = normalizeBillingInterval(billingInterval);
  const monthlyLegacy = process.env.RAZORPAY_PLAN_ID_PRO?.trim() || null;
  const monthly = process.env.RAZORPAY_PLAN_ID_PRO_MONTHLY?.trim() || monthlyLegacy;
  const annual = process.env.RAZORPAY_PLAN_ID_PRO_ANNUAL?.trim() || null;

  if (bi === "annual") return annual || null;
  return monthly || null;
}

/**
 * Razorpay's Node client rejects with `{ statusCode, error }` (not `Error`) — see `node_modules/razorpay/dist/api.js` `normalizeError`.
 * Without this, `e.message` is empty and clients only see an opaque 500.
 */
export function describeRazorpayThrown(value) {
  if (value && typeof value === "object" && "error" in value) {
    const er = value.error;
    let description = "";
    if (typeof er === "string") {
      description = er;
    } else if (er && typeof er === "object") {
      description =
        typeof er.description === "string" && er.description.trim() ?
          er.description.trim()
        : typeof er.message === "string" && er.message.trim() ?
          er.message.trim()
        : "";
      if (!description) {
        try {
          description = JSON.stringify(er);
        } catch {
          description = "Razorpay error";
        }
      }
    } else {
      description = String(er);
    }
    const code =
      er && typeof er === "object" && typeof er.code === "string" && er.code.trim() ? er.code.trim() : null;
    const source =
      er && typeof er === "object" && typeof er.source === "string" && er.source.trim() ? er.source.trim() : null;
    return {
      kind: "razorpay",
      statusCode: typeof value.statusCode === "number" ? value.statusCode : null,
      code,
      source,
      description,
      raw: value,
    };
  }
  if (value instanceof Error) {
    return { kind: "exception", description: value.message || String(value), raw: value };
  }
  return { kind: "unknown", description: String(value), raw: value };
}

/**
 * Creates a Razorpay customer, or returns an existing one if the API reports a duplicate
 * (fail_existing is not always honored the same way across regions / API versions).
 * Uses GET /customers?email= as fallback — requires a non-empty email when resolving duplicates.
 *
 * @param {import("razorpay")} rzp
 */
export async function createRazorpayCustomerOrReuse(rzp, { name, email, supabaseUserId }) {
  const notes = { supabase_user_id: String(supabaseUserId) };
  const payload = {
    name: (name || "MediSathi user").trim() || "MediSathi user",
    fail_existing: 1,
    notes,
  };
  const em = typeof email === "string" ? email.trim() : "";
  if (em) payload.email = em;

  try {
    const c = await rzp.customers.create(payload);
    return c.id;
  } catch (first) {
    const d = describeRazorpayThrown(first);
    const msg = (d.description || "").toLowerCase();
    const duplicate =
      d.kind === "razorpay" &&
      (msg.includes("already exists") ||
        msg.includes("customer already") ||
        msg.includes("duplicate"));
    if (!duplicate || !em) {
      throw first;
    }

    const listed = await rzp.api.get({
      url: "/customers",
      data: { email: em, count: 20 },
    });
    const items = Array.isArray(listed?.items) ? listed.items : [];
    const hit = items.find((x) => (x.email || "").toLowerCase() === em.toLowerCase());
    if (!hit?.id) {
      throw first;
    }
    return hit.id;
  }
}

function safeEqualHex(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
  } catch {
    return false;
  }
}

/**
 * @param {Buffer} rawBody
 * @param {string|undefined} signatureHeader
 * @param {string|undefined} secret
 */
export function verifyWebhookSignature(rawBody, signatureHeader, secret) {
  if (!secret || !signatureHeader) return false;
  const expected = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  return safeEqualHex(expected, signatureHeader);
}

/**
 * @param {Record<string, string>} notes
 */
function planSlugFromNotes(notes) {
  if (!notes || typeof notes !== "object") return null;
  const raw =
    typeof notes.plan_slug === "string" ?
      notes.plan_slug
    : typeof notes.supabase_plan_slug === "string" ?
      notes.supabase_plan_slug
    : null;
  const s = String(raw || "")
    .trim()
    .toLowerCase();
  // Legacy Razorpay subscriptions may still carry notes.plan_slug = plus
  if (s === "plus") return "pro";
  if (s === "pro") return s;
  return null;
}

function userIdFromNotes(notes) {
  if (!notes || typeof notes !== "object") return null;
  const id = notes.supabase_user_id;
  return typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id) ? id : null;
}

/**
 * Razorpay subscription: billing period end (`current_end`, etc.) as epoch ms.
 * @returns {number | null}
 */
export function subscriptionBillingPeriodEndMs(sub) {
  if (!sub || typeof sub !== "object") return null;
  const keys = ["current_end", "end_at", "ended_at", "charge_at"];
  for (const k of keys) {
    const raw = sub[k];
    if (raw == null) continue;
    if (typeof raw === "number" && Number.isFinite(raw)) {
      return raw > 1e12 ? raw : raw * 1000;
    }
    const n = Number(raw);
    if (Number.isFinite(n)) {
      return n > 1e12 ? n : n * 1000;
    }
    const t = Date.parse(String(raw));
    if (!Number.isNaN(t)) return t;
  }
  return null;
}

/**
 * Apply subscription state to Supabase entitlements (service role).
 */
export async function applySubscriptionToEntitlements(subscriptionEntity) {
  const admin = getSupabaseAdmin();
  if (!admin) {
    console.error("SUPABASE_SERVICE_ROLE_KEY missing — cannot apply Razorpay subscription");
    return { ok: false, reason: "no_admin_client" };
  }

  const sub = subscriptionEntity;
  const notes = sub?.notes && typeof sub.notes === "object" ? sub.notes : {};
  const userId = userIdFromNotes(notes);
  let planSlug = planSlugFromNotes(notes);

  const status = String(sub?.status || "").toLowerCase();
  const id = typeof sub?.id === "string" ? sub.id : null;
  const custId = typeof sub?.customer_id === "string" ? sub.customer_id : null;

  if (!userId) {
    console.warn("Razorpay subscription webhook: missing notes.supabase_user_id", sub?.id);
    return { ok: false, reason: "no_user_in_notes" };
  }

  const now = Date.now();

  async function downgradeToFree() {
    const { error } = await admin
      .from("user_entitlements")
      .update({
        plan_slug: "free",
        razorpay_subscription_id: null,
        razorpay_pro_access_until: null,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", userId);

    if (error) {
      console.error("Downgrade to free failed", error);
      return { ok: false, reason: error.message };
    }
    return { ok: true, action: "downgraded_free", userId };
  }

  /** Definitively over — no more paid access */
  if (status === "expired" || status === "completed") {
    return downgradeToFree();
  }

  /** Payment issues — treat as no longer entitled */
  if (status === "halted") {
    return downgradeToFree();
  }

  /**
   * Cancelled: if the user already paid through current_end, they keep Pro until then
   * (auto-renew off but period still valid). Otherwise free immediately.
   */
  if (status === "cancelled") {
    const endMs = subscriptionBillingPeriodEndMs(sub);
    if (endMs != null && now < endMs) {
      let planSlugC = planSlugFromNotes(notes);
      if (!planSlugC) {
        const planId = typeof sub?.plan_id === "string" ? sub.plan_id : "";
        const monthly =
          process.env.RAZORPAY_PLAN_ID_PRO_MONTHLY?.trim() || process.env.RAZORPAY_PLAN_ID_PRO?.trim() || null;
        const annual = process.env.RAZORPAY_PLAN_ID_PRO_ANNUAL?.trim() || null;
        if (planId && monthly && planId === monthly) planSlugC = "pro";
        if (!planSlugC && planId && annual && planId === annual) planSlugC = "pro";
      }
      if (!planSlugC) planSlugC = "pro";

      const row = {
        plan_slug: planSlugC,
        razorpay_subscription_id: id,
        razorpay_pro_access_until: new Date(endMs).toISOString(),
        updated_at: new Date().toISOString(),
      };
      if (custId) row.razorpay_customer_id = custId;

      const { data: existing, error: selErr } = await admin.from("user_entitlements").select("user_id").eq("user_id", userId).maybeSingle();
      if (selErr) {
        console.error(selErr);
        return { ok: false, reason: selErr.message };
      }
      if (!existing) {
        const ins = { user_id: userId, ...row };
        const { error: insErr } = await admin.from("user_entitlements").insert(ins);
        if (insErr) {
          console.error(insErr);
          return { ok: false, reason: insErr.message };
        }
      } else {
        const { error: updErr } = await admin.from("user_entitlements").update(row).eq("user_id", userId);
        if (updErr) {
          console.error(updErr);
          return { ok: false, reason: updErr.message };
        }
      }
      return { ok: true, action: "pro_until_prepaid_end", userId, untilMs: endMs };
    }
    return downgradeToFree();
  }

  if (status !== "active" && status !== "authenticated") {
    return { ok: true, action: "ignored_non_active", userId, status };
  }

  if (!planSlug) {
    const planId = typeof sub?.plan_id === "string" ? sub.plan_id : "";
    const monthly =
      process.env.RAZORPAY_PLAN_ID_PRO_MONTHLY?.trim() || process.env.RAZORPAY_PLAN_ID_PRO?.trim() || null;
    const annual = process.env.RAZORPAY_PLAN_ID_PRO_ANNUAL?.trim() || null;
    if (planId && monthly && planId === monthly) planSlug = "pro";
    if (!planSlug && planId && annual && planId === annual) planSlug = "pro";
  }

  if (!planSlug) {
    console.warn("Razorpay subscription: could not resolve plan_slug", sub?.id, status);
    return { ok: false, reason: "no_plan_slug" };
  }

  const periodEndMs = subscriptionBillingPeriodEndMs(sub);
  const periodEndIso =
    periodEndMs != null && Number.isFinite(periodEndMs) ? new Date(periodEndMs).toISOString() : null;

  const row = {
    plan_slug: planSlug,
    razorpay_subscription_id: id,
    /** End of current paid period (Razorpay `current_end` / equivalent). Updates each cycle on renewal. */
    razorpay_pro_access_until: periodEndIso,
    updated_at: new Date().toISOString(),
  };
  if (custId) row.razorpay_customer_id = custId;

  const { data: existing, error: selErr } = await admin.from("user_entitlements").select("user_id").eq("user_id", userId).maybeSingle();

  if (selErr) {
    console.error(selErr);
    return { ok: false, reason: selErr.message };
  }

  if (!existing) {
    const { error: insErr } = await admin.from("user_entitlements").insert({ user_id: userId, ...row });
    if (insErr) {
      console.error(insErr);
      return { ok: false, reason: insErr.message };
    }
  } else {
    const { error: updErr } = await admin.from("user_entitlements").update(row).eq("user_id", userId);
    if (updErr) {
      console.error(updErr);
      return { ok: false, reason: updErr.message };
    }
  }

  return { ok: true, action: "plan_applied", userId, planSlug };
}

/**
 * Express handler: raw JSON body buffer (use express.raw).
 */
export async function handleRazorpayWebhook(req, res) {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET?.trim();
  if (!secret) {
    res.status(503).json({ error: "RAZORPAY_WEBHOOK_SECRET not configured" });
    return;
  }

  const sig = req.headers["x-razorpay-signature"];
  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body || "", "utf8");

  if (!verifyWebhookSignature(raw, typeof sig === "string" ? sig : "", secret)) {
    res.status(400).json({ error: "Invalid webhook signature" });
    return;
  }

  let json;
  try {
    json = JSON.parse(raw.toString("utf8"));
  } catch {
    res.status(400).json({ error: "Invalid JSON" });
    return;
  }

  const event = json?.event;

  try {
    if (json?.payload?.subscription?.entity) {
      await applySubscriptionToEntitlements(json.payload.subscription.entity);
    }

    if (event === "payment.captured" && json?.payload?.payment?.entity) {
      const pay = json.payload.payment.entity;
      const subId = typeof pay?.subscription_id === "string" ? pay.subscription_id : null;
      if (subId && getRazorpay()) {
        try {
          const entity = await getRazorpay().subscriptions.fetch(subId);
          if (entity?.id) await applySubscriptionToEntitlements(entity);
        } catch (e) {
          console.error("Could not fetch subscription after payment", e);
        }
      }
    }
  } catch (e) {
    console.error("Webhook handler error", e);
    res.status(500).json({ error: "webhook_processing_failed" });
    return;
  }

  res.json({ ok: true });
}
