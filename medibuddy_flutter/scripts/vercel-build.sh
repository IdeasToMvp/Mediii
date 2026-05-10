#!/usr/bin/env bash
# Vercel (Linux): install Flutter SDK, build web bundle with dart-defines from env vars.
#
# Set in Vercel → Settings → Environment Variables (Production / Preview as needed):
#   SUPABASE_URL
#   SUPABASE_ANON_KEY
#   API_BASE_URL   (e.g. https://mediii-production.up.railway.app — no trailing slash)

set -euo pipefail
export GIT_TERMINAL_PROMPT=0

echo "Vercel env: VERCEL_ENV=${VERCEL_ENV:-<unset>}"

missing=()
[[ -z "${SUPABASE_URL:-}" ]] && missing+=("SUPABASE_URL")
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing+=("SUPABASE_ANON_KEY")
[[ -z "${API_BASE_URL:-}" ]] && missing+=("API_BASE_URL")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing required environment variables: ${missing[*]}"
  echo "Add them in Vercel → Project → Settings → Environment Variables."
  echo "Enable each for the same target as this deploy (Production *and* Preview if you use both), then Redeploy."
  exit 1
fi

FLUTTER_DIR="${PWD}/.flutter-sdk"

if [[ ! -x "${FLUTTER_DIR}/bin/flutter" ]]; then
  rm -rf "${FLUTTER_DIR}"
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

flutter config --enable-web --no-analytics >/dev/null
flutter precache --web
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=API_BASE_URL="${API_BASE_URL}"
