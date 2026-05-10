import "dotenv/config";
import cors from "cors";
import express from "express";
import multer from "multer";
import { createClient } from "@supabase/supabase-js";
import OpenAI from "openai";
import { analyzePrescriptionImage } from "./openaiPrescription.js";

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

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
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

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "medibuddy-api" });
});

/**
 * Analyze an uploaded prescription image (does not persist).
 */
app.post("/api/prescriptions/analyze-image", requireUser, upload.single("image"), async (req, res) => {
  try {
    if (!req.file) {
      res.status(400).json({ error: "multipart field \"image\" is required" });
      return;
    }
    const mime = req.file.mimetype || "image/jpeg";
    if (!/^image\/(jpeg|png|webp|gif)$/.test(mime)) {
      res.status(400).json({ error: "Unsupported image type (use jpeg, png, webp, or gif)" });
      return;
    }
    const parsed = await analyzePrescriptionImage(openai, req.file.buffer, mime);
    res.json({ analysis: parsed });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Analysis failed", detail: String(e.message || e) });
  }
});

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
    const buffer = Buffer.from(b64, "base64");
    const parsed = await analyzePrescriptionImage(openai, buffer, mime);
    res.json({ analysis: parsed });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Analysis failed", detail: String(e.message || e) });
  }
});

/**
 * Create a prescription row (manual or post-analysis).
 */
app.post("/api/prescriptions", requireUser, async (req, res) => {
  try {
    const body = req.body || {};
    const source = body.source === "analyzed" ? "analyzed" : "manual";
    const payload = {
      user_id: req.user.id,
      title: typeof body.title === "string" ? body.title : null,
      doctor_name: typeof body.doctor_name === "string" ? body.doctor_name : null,
      patient_name: typeof body.patient_name === "string" ? body.patient_name : null,
      prescription_date: typeof body.prescription_date === "string" ? body.prescription_date : null,
      diagnosis: typeof body.diagnosis === "string" ? body.diagnosis : null,
      general_instructions:
        typeof body.general_instructions === "string" ? body.general_instructions : null,
      medications: Array.isArray(body.medications) ? body.medications : [],
      extraction_notes:
        typeof body.extraction_notes === "string" ? body.extraction_notes : null,
      raw_analysis:
        body.raw_analysis !== undefined && body.raw_analysis !== null ? body.raw_analysis : null,
      source,
    };

    const { data, error } = await req.supabase.from("prescriptions").insert(payload).select("*").single();
    if (error) {
      console.error(error);
      res.status(400).json({ error: error.message });
      return;
    }
    res.status(201).json({ prescription: data });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Save failed", detail: String(e.message || e) });
  }
});

app.get("/api/prescriptions", requireUser, async (req, res) => {
  const { data, error } = await req.supabase
    .from("prescriptions")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) {
    res.status(400).json({ error: error.message });
    return;
  }
  res.json({ prescriptions: data || [] });
});

app.get("/api/prescriptions/:id", requireUser, async (req, res) => {
  const { data, error } = await req.supabase.from("prescriptions").select("*").eq("id", req.params.id).maybeSingle();
  if (error) {
    res.status(400).json({ error: error.message });
    return;
  }
  if (!data) {
    res.status(404).json({ error: "Not found" });
    return;
  }
  res.json({ prescription: data });
});

app.listen(PORT, () => {
  console.log(`MediBuddy API listening on http://localhost:${PORT}`);
});
