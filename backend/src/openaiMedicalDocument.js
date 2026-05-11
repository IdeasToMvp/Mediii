import OpenAI from "openai";

const EXTRACTION_SYSTEM = `You are a clinical document structuring assistant.

Rules:
- Return ONLY JSON matching the schema we request.
- Classify clearly: a "prescription" contains medication orders. A "report" is labs, diagnostics, imaging summaries, glucose logs, pathology, vitals summaries, discharge summaries focused on readings/metrics—not new medications.
- If mixed, prefer "prescription" when clear medication lines exist; otherwise "report".
- Never invent diagnoses, medications, or numeric lab values — use null, empty arrays, or flag uncertainty inside extraction_notes.
- Do not provide medical advice.

Output JSON MUST include:
 document_kind — "prescription" | "report"

If document_kind === "prescription":
- patient_name: string|null
- doctor_name: string|null
- prescription_date: string|null
- clinic_or_hospital: string|null
- diagnosis: string|null
- medications: array of { name, dosage, frequency, duration (how long to take: e.g. "7 days","14","2 weeks","30 days", or null if unclear/open-ended), instructions } (instructions may summarize meal cues like "before breakfast")
- general_instructions: string|null
- extraction_notes: string|null
- report_summary: null

If document_kind === "report":
- patient_name, doctor_name, record_date string|null (reuse prescription_date as record_date semantic)
- report_summary REQUIRED object shaped as:
  {
    metric_label: string (e.g. "BLOOD GLUCOSE"),
    unit: string|null (e.g. "mg/dL"),
    headline_value: number|null,
    headline_status_label: string|null ("STABLE"|"HIGH"|"LOW"| etc. short badge),
    series: [{ "label": string (date or ordinal), "value": number }] up to last 14 points if evident
  }
- medications MUST be []
- prescription_date MAY duplicate record_date`

/**
 * Analyze a clinic image; returns unified shape with prescription fields and/or report_summary.
 * @param {OpenAI} openaiClient
 * @param {Buffer} imageBuffer
 * @param {string} mimeType
 */
export async function analyzeMedicalDocumentImage(openaiClient, imageBuffer, mimeType) {
  const b64 = imageBuffer.toString("base64");
  const dataUrl = `data:${mimeType};base64,${b64}`;

  const response = await openaiClient.chat.completions.create({
    model: process.env.OPENAI_VISION_MODEL || "gpt-4o-mini",
    messages: [
      { role: "system", content: EXTRACTION_SYSTEM },
      {
        role: "user",
        content: [
          {
            type: "text",
            text: `Read this healthcare document photo and reply with ONE JSON object as described above.
Populate prescription_date OR (for reports) reuse the clearest dated line as prescription_date.`,
          },
          { type: "image_url", image_url: { url: dataUrl } },
        ],
      },
    ],
    response_format: { type: "json_object" },
    max_tokens: 1600,
  });

  const text = response.choices[0]?.message?.content;
  if (!text) throw new Error("Empty model response");

  try {
    return JSON.parse(text);
  } catch {
    throw new Error("Model returned invalid JSON");
  }
}
