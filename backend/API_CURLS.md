## MediBuddy / MediSathi API — `curl` examples

Replace:

- **`$API`** — backend base URL, e.g. `http://localhost:3200`
- **`$TOKEN`** — Supabase `access_token` (JWT from the signed-in user)

All authenticated routes send:

```bash
curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" ...
```

---

### Health (no auth)

```bash
curl -sS "$API/api/health"
```

---

### Bootstrap profile + entitlement summary

Ensures rows in `user_profiles` / `user_entitlements`; returns AI budget and plan limits.

```bash
curl -sS "$API/api/me" \
  -H "Authorization: Bearer $TOKEN"
```

---

### List subscription catalog (plans + limits)

```bash
curl -sS "$API/api/subscription/plans" \
  -H "Authorization: Bearer $TOKEN"
```

---

### Razorpay subscriptions (mobile / hosted checkout)

Set env vars in `backend/.env.example`, create **Plans** in Razorpay Dashboard, and point a **Webhook** to:

`https://<your-api-host>/api/billing/razorpay/webhook`

Use the webhook secret as **`RAZORPAY_WEBHOOK_SECRET`**. The server needs **`SUPABASE_SERVICE_ROLE_KEY`** so webhooks can update `user_entitlements`.

**Checkout config** (publishable key and currency for the client):

```bash
curl -sS "$API/api/billing/razorpay/config" \
  -H "Authorization: Bearer $TOKEN"
```

**Create subscription** (returns `key_id`, `subscription_id`, optional `short_url` for web):

```bash
# Monthly Pro (uses RAZORPAY_PLAN_ID_PRO_MONTHLY)
curl -sS -X POST "$API/api/billing/razorpay/create-subscription" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"plan_slug":"pro","customer_notify":true,"billing_interval":"monthly"}'

# Annual Pro (uses RAZORPAY_PLAN_ID_PRO_ANNUAL)
curl -sS -X POST "$API/api/billing/razorpay/create-subscription" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"plan_slug":"pro","customer_notify":true,"billing_interval":"annual"}'
```

After payment, webhooks (or **`POST /api/billing/razorpay/sync-subscription`**) map the subscription to **`pro`** once Razorpay reports **`active`** or **`authenticated`**.

**Sync immediately after Checkout** (when webhooks lag — e.g. localhost, or cold start):

```bash
curl -sS -X POST "$API/api/billing/razorpay/sync-subscription" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"subscription_id":"sub_xxxxxxxxxxxxxx"}'
```

---

### AI document extraction (classification: prescription vs report)

Counts **one** AI extraction toward the caller’s monthly plan limit **after** successful model output.

Multipart:

```bash
curl -sS -X POST "$API/api/prescriptions/analyze-image" \
  -H "Authorization: Bearer $TOKEN" \
  -F "image=@/path/to/photo.jpg"
```

JSON / base64 (mobile/web friendly):

```bash
curl -sS -X POST "$API/api/prescriptions/analyze-image-json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mime_type":"image/jpeg","image_base64":"<BASE64_HERE>"}'
```

Responses include `analysis.document_kind` (`prescription`|`report`). Reports embed `report_summary` (labels, headline value, badge, optional `series[]` chart points).

Quota exhausted → **402** JSON with `quota` envelope.

---

### Create stored record (manual or post-analysis)

`document_kind` defaults to `prescription`. For uploads classified as labs/diagnostics send `report` + structured `report_summary`.

**Analyzed uploads** (`source: "analyzed"`): the API defaults to **auto_resolve_patient_family_member** and **auto_generate_reminders**. It matches `patient_name` against your `family_members` (exact/substring/shared word); if none match and you still have household profiles, it assigns **one at random**, then stores that in `patient_family_member_id`. It also creates **medicine_schedules** from each medication line (`prescription_date` → `start_date`; `duration` text → `end_date`; `frequency`/`instructions` → `time_points`). Set either flag to `false` to skip, or pass `patient_family_member_id` explicitly. Requires migration `003_prescription_patient_member.sql`. Responses include `patient_family_resolution` and `reminders` (`generated`, `schedules`, optional `error`).

```bash
curl -sS -X POST "$API/api/prescriptions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<JSON
{
  "source": "analyzed",
  "document_kind": "prescription",
  "title": "City Clinic — follow-up",
  "patient_name": "Sarah",
  "doctor_name": "Dr. Rao",
  "prescription_date": "2026-05-09",
  "diagnosis": "Hypertension",
  "medications": [
    {
      "name": "Metformin",
      "dosage": "500mg",
      "frequency": "twice daily",
      "duration": "30 days",
      "instructions": "With lunch"
    }
  ]
}
JSON
```

Report example:

```bash
curl -sS -X POST "$API/api/prescriptions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<JSON
{
  "source": "analyzed",
  "document_kind": "report",
  "title": "Home glucose log",
  "patient_name": "Sarah",
  "prescription_date": "2026-05-07",
  "medications": [],
  "report_summary": {
    "metric_label": "BLOOD GLUCOSE",
    "unit": "mg/dL",
    "headline_value": 94,
    "headline_status_label": "STABLE",
    "series": [
      { "label": "Mon", "value": 99 },
      { "label": "Tue", "value": 97 },
      { "label": "Wed", "value": 96 },
      { "label": "Thu", "value": 95 },
      { "label": "Fri", "value": 94 },
      { "label": "Sat", "value": 93 },
      { "label": "Sun", "value": 94 }
    ]
  },
  "raw_analysis": {}
}
JSON
```

---

### List prescriptions / reports separately

All records:

```bash
curl -sS "$API/api/prescriptions" \
  -H "Authorization: Bearer $TOKEN"
```

Prescriptions only:

```bash
curl -sS "$API/api/prescriptions?kind=prescription" \
  -H "Authorization: Bearer $TOKEN"
```

Reports / labs only:

```bash
curl -sS "$API/api/prescriptions?kind=report" \
  -H "Authorization: Bearer $TOKEN"
```

Single row:

```bash
curl -sS "$API/api/prescriptions/<PRESCRIPTION_UUID>" \
  -H "Authorization: Bearer $TOKEN"
```

---

### Family members (`max_family_members` enforced by subscription plan)

List + quota gate:

```bash
curl -sS "$API/api/family-members" \
  -H "Authorization: Bearer $TOKEN"
```

Create (requires unused slot vs plan ceiling → **402** when full):

```bash
curl -sS -X POST "$API/api/family-members" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"display_name":"Mom","relation":"mother","birth_year":1962}'
```

Partial update:

```bash
curl -sS -X PATCH "$API/api/family-members/<MEMBER_UUID>" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"display_name":"Mother","notes":"Nut allergy noted"}'
```

Delete:

```bash
curl -sS -X DELETE "$API/api/family-members/<MEMBER_UUID>" \
  -H "Authorization: Bearer $TOKEN"
```

---

### Medicine schedules (manual recurring + Rx-generated)

Definitions:

```bash
curl -sS "$API/api/medicine-schedules" \
  -H "Authorization: Bearer $TOKEN"
```

Create manual (`time_points`: array of `"HH:mm"` UTC clock times):

```bash
curl -sS -X POST "$API/api/medicine-schedules" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "medication_name": "Metformin 500mg",
    "dosage_text": "500 mg",
    "meal_instruction": "With lunch",
    "schedule_kind": "daily",
    "time_points": ["13:30"],
    "start_date": "2026-05-10"
  }'
```

Update:

```bash
curl -sS -X PATCH "$API/api/medicine-schedules/<SCHEDULE_UUID>" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"time_points":["08:00","21:00"]}'
```

Delete:

```bash
curl -sS -X DELETE "$API/api/medicine-schedules/<SCHEDULE_UUID>" \
  -H "Authorization: Bearer $TOKEN"
```

Flattened upcoming doses (today + horizon, default **3 days**):

```bash
curl -sS "$API/api/medicine-schedules/upcoming?days=3" \
  -H "Authorization: Bearer $TOKEN"
```

---

### Bulk-generate schedules from a prescription

Walks structured `medications[]` rows and emits best-effort `daily`/`time_points` heuristics (always review in UI/clinical workflow).

```bash
curl -sS -X POST "$API/api/medicine-schedules/from-prescription" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prescription_id":"<PRESCRIPTION_UUID>",
    "family_member_id":null,
    "default_times":["09:00","21:00"]
  }'
```

---

### Operational notes

- Apply SQL migration `supabase/migrations/002_dashboard_feature.sql` after `001_prescriptions.sql` so `document_kind` / quotas exist.
- `user_entitlements` rows are seeded via RPC `ensure_user_entitlements`; clients cannot spoof plan upgrades directly (Stripe/webhooks will use the service role in production).
- Family seat checks run through `can_add_family_member`; AI metering uses `increment_ai_extractions`.
