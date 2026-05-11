# MediBuddy

Cross-platform app (**Flutter**: iOS, Android, Web) with a small **Node.js** API and **Supabase** for Google sign-in and Postgres storage. Prescriptions can be entered manually or extracted from a photo via **OpenAI** (vision).

---

## Repository layout

| Path | Purpose |
|------|---------|
| `medibuddy_flutter/` | Flutter app (targets iOS, Android, Web) |
| `backend/` | Express API (`/api/health`, prescriptions + OpenAI analyze) |
| `supabase/migrations/001_prescriptions.sql` | Run in Supabase SQL editor to create `prescriptions` + RLS |

---

## 1) Supabase setup

1. Create a project at [https://supabase.com](https://supabase.com).
2. **SQL**: run migrations in `supabase/migrations/` in order (`001` onward). For app releases apply at least **`011`**–**`014`** (platform column).
3. **Auth → Providers → Google**: enable Google; add your OAuth client IDs from Google Cloud Console (Web / iOS / Android as needed).
4. **Auth → URL configuration**:
   - Add **Redirect URLs** including:
     - `io.medibuddy.app://login-callback/` (iOS / Android deep link used by this project)
     - Your Flutter web origin(s), e.g. `http://localhost:XXXX/` and your production web URL.
   - Set **Site URL** to your primary app URL (for web, often `http://localhost:PORT` during dev).

Copy **Project URL** and **anon public key** from **Project Settings → API** (used by Flutter and the backend).

---

## 2) Backend (Node)

```bash
cd backend
cp .env.example .env
# Edit .env: OPENAI_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY
npm install
npm run dev
```

Default listen: `http://localhost:3200`

The API verifies the caller by treating the `Authorization: Bearer` value as a Supabase **access token** (`getUser()`).

### Android / iOS artifacts (Postman)

1. Apply migrations **`011_app_releases`** (table + bucket), **`012`** (bucket limit), **`013`** (`apk_download_url`), **`014`** (`platform` column — `android` \| `ios`).
2. Set **`SUPABASE_SERVICE_ROLE_KEY`** and **`APK_ADMIN_UPLOAD_TOKEN`** on the server (`backend/.env.example`).

**Option A — multipart upload to Storage:** `POST /api/admin/app-releases` (`multipart/form-data`), header **`X-Admin-Upload-Token`**. Fields: **`apk`** (file — `.apk` when `platform` is `android`, `.ipa` when `ios`), **`version`**, **`version_code`**, optional **`release_notes`**, **`channel`**, **`platform`** or **`build_type`** (`android` \| `ios`, default `android`).

**Option B — hosted HTTPS link (JSON):** `POST /api/admin/app-releases/link` with `Content-Type: application/json`, same header. Body includes **`download_url`**, **`version`**, **`version_code`**, optional **`platform`** / **`build_type`**, **`release_notes`**, **`channel`**, **`apk_filename`**, **`apk_byte_size`**.

Example (Android + Drive link):

```bash
curl -X POST "$API/api/admin/app-releases/link" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Upload-Token: $TOKEN" \
  -d '{"download_url":"https://drive.google.com/file/d/FILE_ID/view","version":"1.2.0","version_code":20,"platform":"android","release_notes":"Bug fixes"}'
```

iOS link (structure ready for TestFlight / hosted IPA):

```bash
curl -X POST "$API/api/admin/app-releases/link" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Upload-Token: $TOKEN" \
  -d '{"download_url":"https://…","version":"1.2.0","version_code":20,"build_type":"ios","apk_filename":"MediSathi.ipa"}'
```

**Public:** `GET /api/app-releases/latest?channel=production&platform=android` (or `platform=ios`). **`GET /api/app-releases/:id/download-url`** returns a signed Storage URL or the stored HTTPS link.

Optional env: **`APK_DOWNLOAD_URL_TTL_SEC`** for **Storage-backed** signed URLs only.

**Optional:** override vision model (default `gpt-4o-mini`):

```bash
OPENAI_VISION_MODEL=gpt-4o
```

### Railway (API hosting)

Monorepo: there is **no** root `package.json`, so [Railpack](https://docs.railway.com/builds/build-configuration) at the repo root cannot auto-detect Node. This repo uses a **`Dockerfile`** under `backend/` instead (see [`railway.toml`](railway.toml) at the repo root).

1. Link the GitHub repo and create a service for the API.
2. **Root Directory**: leave **`/` empty** (default). The Dockerfile is referenced as `backend/Dockerfile` from the **full checkout**.
3. **Config as Code** path: **`/railway.toml`** (still repo-root-relative; it does **not** follow Root Directory — same docs link above).
4. **Variables**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENAI_API_KEY` (optional: `OPENAI_VISION_MODEL`). Railway sets **`PORT`**; the server reads `process.env.PORT`.

Alternative (Railpack only): set **Root Directory** to `backend` and keep the config manifest beside `backend/package.json`. The Dockerfile route avoids Railpack guessing wrong when manifests live only at `/railway.toml`.

---

## 3) Flutter app

The app reads config from **compile-time** `--dart-define` flags (avoids committing secrets).

### iOS Simulator / macOS / desktop (API on same machine)

```bash
cd medibuddy_flutter
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_JWT \
  --dart-define=API_BASE_URL=http://127.0.0.1:3200
```

### Android Emulator (host API)

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_JWT \
  --dart-define=API_BASE_URL=http://10.0.2.2:3200
```

### Web (Chrome)

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_JWT \
  --dart-define=API_BASE_URL=http://localhost:3200
```

### Vercel (Flutter Web)

The Flutter web artifact must come from **`flutter build web`** (output: `build/web`). Do **not** set Root Directory to `medibuddy_flutter/web` (sources only).

1. **Vercel** → Project → Settings → General / Build & Deploy:
   - **Root Directory:** `medibuddy_flutter`
   - **Framework Preset:** Other (optional; avoids wrong auto-detect).
   - **Build Command:** (optional if you use repo `vercel.json`) defaults to script below.
   - **Output Directory:** `build/web` (must match `vercel.json` if present).
   - **Install Command:** can be noop / skip for Flutter-only root (handled in `medibuddy_flutter/vercel.json`).

2. **Environment variables** (required at **build** time — `--dart-define` is baked into the wasm/js bundle):
   - `SUPABASE_URL` — Supabase project URL
   - `SUPABASE_ANON_KEY` — Supabase anon (public) key
   - `API_BASE_URL` — HTTPS API URL, e.g. `https://your-service.up.railway.app` (no trailing slash)

   **Important:** In Vercel, each variable must be enabled for every environment you deploy to. If you only tick **Production**, builds for **Preview** (e.g. Git PRs or first import) will fail with “Missing required environment variables”. Either add the same three keys for **Preview** (and **Development** if you run `vercel dev`) or deploy from the **production** branch only. After saving variables, trigger a **Redeploy**.

3. SPA routing: [`medibuddy_flutter/vercel.json`](medibuddy_flutter/vercel.json) rewrites deep links to `index.html`.

4. **Supabase Auth** URLs: add your Vercel origin(s), e.g. `https://<project>.vercel.app`, under **Redirect URLs** / **Site URL** as needed.

5. Local dry run from `medibuddy_flutter`:

   ```bash
   export SUPABASE_URL=...
   export SUPABASE_ANON_KEY=...
   export API_BASE_URL=https://your-api.example.com
   bash scripts/vercel-build.sh
   ```

**CORS:** the backend enables `cors()` broadly for local dev; tighten `origin` before production.

---

## 4) Getting a Supabase `access_token` for manual API testing

Use the Supabase REST auth endpoint (email/password is **not** configured in this starter—use **Google** in the app first, or use the Supabase Dashboard “Generate link” / client session from your dev tools).

Practical approach after signing in inside the app: copy the **access token** from Supabase session debug output or from your browser’s local storage for Flutter web (look for keys under your Supabase URL / `sb-` keys). Use that string as `ACCESS_TOKEN` below.

---

## 5) HTTP API — `curl` examples

Replace:

- `ACCESS_TOKEN` — Supabase JWT access token for your signed-in user  
- `BASE` — `http://localhost:3200` (or your deployed API base)  
- `./rx.jpg` — path to a JPEG/PNG prescription image  

### Health check (no auth)

```bash
curl -sS "$BASE/api/health"
```

Example:

```bash
curl -sS "http://localhost:3200/api/health"
```

### List prescriptions (auth required)

```bash
curl -sS "$BASE/api/prescriptions" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

### Create manual prescription (JSON)

```bash
curl -sS "$BASE/api/prescriptions" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "manual",
    "title": "Clinic visit",
    "patient_name": "Alex Example",
    "doctor_name": "Dr. Rao",
    "prescription_date": "2026-05-10",
    "diagnosis": "Hypertension",
    "general_instructions": "Take after food. Follow up in 2 weeks.",
    "medications": [
      {
        "name": "Amlodipine",
        "dosage": "5 mg",
        "frequency": "Once daily",
        "duration": "30 days",
        "instructions": "Morning"
      }
    ]
  }'
```

### Analyze prescription image (multipart, does not save)

```bash
curl -sS "$BASE/api/prescriptions/analyze-image" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -F "image=@./rx.jpg;type=image/jpeg"
```

### Analyze image via JSON + base64 (auth required)

```bash
B64="$(base64 -i ./rx.jpg)"
curl -sS "$BASE/api/prescriptions/analyze-image-json" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"image_base64\":\"$B64\",\"mime_type\":\"image/jpeg\"}"
```

### Fetch one prescription by id

```bash
curl -sS "$BASE/api/prescriptions/PRESCRIPTION_UUID" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

### Typical “upload flow”

1. Call `analyze-image` → review JSON `analysis` in the response  
2. Correct fields client-side, then `POST /api/prescriptions` with `"source": "analyzed"` and `raw_analysis` set to the parsed object (the Flutter app mirrors this)

Example save after analysis:

```bash
curl -sS "$BASE/api/prescriptions" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "analyzed",
    "title": "City Clinic",
    "patient_name": null,
    "doctor_name": "Dr. Rao",
    "prescription_date": "2026-05-10",
    "diagnosis": null,
    "general_instructions": null,
    "extraction_notes": "Handwriting partially unclear",
    "medications": [
      {
        "name": "Amlodipine",
        "dosage": "5 mg",
        "frequency": "QD",
        "duration": null,
        "instructions": null
      }
    ],
    "raw_analysis": { "note": "store the exact OpenAI-shaped JSON here" }
  }'
```

---

## Notes & disclaimer

MediBuddy is a **technical starter**, not medical advice. OCR/LLM extraction can be wrong; users must verify medicines with a licensed clinician or pharmacist before acting on extracted data.

If inserts fail with Row Level Security errors, confirm the migration ran and `Authorization` carries the signed-in **user access token**, not only the anon key alone.

