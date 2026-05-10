import OpenAI from "openai";

const EXTRACTION_SYSTEM = `You are a medical document assistant. Extract structured data from prescription images or text.
Rules:
- Return ONLY valid JSON matching the requested schema.
- Never invent diagnoses or medications if illegible — use null or empty arrays and put uncertainty in extraction_notes.
- Do not give medical advice.`;

export async function analyzePrescriptionImage(openaiClient, imageBuffer, mimeType) {
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
            text: `Read this prescription or medical note and extract JSON with this shape:
{
  "patient_name": string | null,
  "doctor_name": string | null,
  "prescription_date": string | null,
  "clinic_or_hospital": string | null,
  "diagnosis": string | null,
  "medications": [
    {
      "name": string,
      "dosage": string | null,
      "frequency": string | null,
      "duration": string | null,
      "instructions": string | null
    }
  ],
  "general_instructions": string | null,
  "extraction_notes": string | null
}`,
          },
          { type: "image_url", image_url: { url: dataUrl } },
        ],
      },
    ],
    response_format: { type: "json_object" },
    max_tokens: 1200,
  });

  const text = response.choices[0]?.message?.content;
  if (!text) throw new Error("Empty model response");

  try {
    return JSON.parse(text);
  } catch {
    throw new Error("Model returned invalid JSON");
  }
}
