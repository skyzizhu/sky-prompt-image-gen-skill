#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config/prompt_image_gen.conf}"
ENV_IMAGE_SIZE="${IMAGE_SIZE-}"
ENV_ASPECT_RATIO="${ASPECT_RATIO-}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

BASE_URL="${BASE_URL:?missing BASE_URL in config}"
MODEL="${MODEL:-gemini-3-pro-image-preview}"
IMAGE_SIZE="${IMAGE_SIZE:-2K}"
ASPECT_RATIO="${ASPECT_RATIO:-16:9}"
if [[ -n "$ENV_IMAGE_SIZE" ]]; then
  IMAGE_SIZE="$ENV_IMAGE_SIZE"
fi

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"
MAX_TIME="${MAX_TIME:-180}"
RETRY_MAX="${RETRY_MAX:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"
DEBUG="${DEBUG:-0}"

API_KEY="${GEMINI_IMAGE_API_KEY:?missing GEMINI_IMAGE_API_KEY}"

if [[ -n "${1-}" ]]; then
  PROMPT="$1"
else
PROMPT="${PROMPT:?missing PROMPT}"
fi

COUNT="${COUNT:-1}"
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "COUNT must be a positive integer" >&2
  exit 1
fi

OUT_DIR="image_out/$(date +%Y%m%d)"
mkdir -p "$OUT_DIR"

OUT_PREFIX="${OUT_PREFIX:-generated}"
OUT="${OUT:-}"

if [[ -n "$ENV_ASPECT_RATIO" ]]; then
  ASPECT_RATIO="$ENV_ASPECT_RATIO"
fi
if [[ -n "$ENV_IMAGE_SIZE" ]]; then
  IMAGE_SIZE="$ENV_IMAGE_SIZE"
fi

# Debuggable hint for which aspect ratio/image size is used (if provided).
if [[ -n "$ENV_ASPECT_RATIO" ]]; then
  echo "using_aspect_ratio ${ASPECT_RATIO} (source=env)"
fi
if [[ -n "$ENV_IMAGE_SIZE" ]]; then
  echo "using_image_size ${IMAGE_SIZE} (source=env)"
fi

debug() {
  if [[ "$DEBUG" == "1" ]]; then
    echo "$@"
  fi
}

next_available_path() {
  local raw="$1"
  if [[ ! -e "$raw" ]]; then
    echo "$raw"
    return
  fi
  local base="${raw%.*}"
  local ext="${raw##*.}"
  local i=1
  while [[ -e "${base}(${i}).${ext}" ]]; do
    i=$((i + 1))
  done
  echo "${base}(${i}).${ext}"
}

decode_to_png() {
  local response_file="$1"
  local out_path="$2"
  OUT_PATH="$out_path" python - <<'PY' "$response_file"
import base64
import io
import json
import os
import sys

try:
    from PIL import Image
except Exception:
    print("Missing dependency: pillow. Install with: pip install pillow", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]
try:
    with open(path, "rb") as f:
        data = json.load(f)
except json.JSONDecodeError:
    print("Request failed: non-JSON response", file=sys.stderr)
    sys.exit(1)

if "error" in data:
    print("Request failed:", data["error"], file=sys.stderr)
    sys.exit(1)

candidates = data.get("candidates")
if not isinstance(candidates, list) or not candidates:
    print("Request failed: missing candidates in response", file=sys.stderr)
    sys.exit(1)

raw_b64 = None
for cand in candidates:
    content = cand.get("content", {})
    parts = content.get("parts", [])
    if not isinstance(parts, list):
        continue
    for part in parts:
        inline_data = part.get("inlineData")
        if isinstance(inline_data, dict) and isinstance(inline_data.get("data"), str):
            raw_b64 = inline_data["data"]
            break
    if raw_b64:
        break

if not raw_b64:
    print("Request failed: model returned no image data", file=sys.stderr)
    sys.exit(1)

try:
    raw = base64.b64decode(raw_b64)
except Exception as e:
    print("Request failed: invalid image base64:", str(e), file=sys.stderr)
    sys.exit(1)

out_path = os.environ["OUT_PATH"]
with Image.open(io.BytesIO(raw)) as im:
    im.save(out_path, format="PNG")
print("saved", out_path)
PY
}

start_ts=$(date +%s)
saved_paths=()
tmp_files=()
cleanup() {
  if [[ ${#tmp_files[@]} -gt 0 ]]; then
    rm -f "${tmp_files[@]}" || true
  fi
}
trap cleanup EXIT

for ((idx = 1; idx <= COUNT; idx++)); do
  payload=$(PROMPT="$PROMPT" ASPECT_RATIO="$ASPECT_RATIO" IMAGE_SIZE="$IMAGE_SIZE" python - <<'PY'
import json
import os

payload = {
    "contents": [{
        "role": "user",
        "parts": [{"text": os.environ["PROMPT"]}]
    }],
    "generationConfig": {
        "responseModalities": ["TEXT", "IMAGE"],
        "imageConfig": {
            "aspectRatio": os.environ["ASPECT_RATIO"],
            "imageSize": os.environ["IMAGE_SIZE"],
        }
    }
}
print(json.dumps(payload, ensure_ascii=False))
PY
)

  if [[ -n "$OUT" && "$COUNT" -eq 1 ]]; then
    file_name="$(basename "$OUT")"
    file_name="${file_name%.*}.png"
  else
    file_name="${OUT_PREFIX}_$(printf "%02d" "$idx").png"
  fi
  out_path="$(next_available_path "${OUT_DIR}/${file_name}")"

  tmp_resp="$(mktemp)"
  tmp_files+=("$tmp_resp")

  debug "debug_generation_index ${idx}/${COUNT}"
  debug "debug_request_aspect_ratio ${ASPECT_RATIO}"
  debug "debug_request_image_size ${IMAGE_SIZE}"

  curl_retry_extra=()
  if curl --help all 2>/dev/null | rg -q -- '--retry-all-errors'; then
    curl_retry_extra+=(--retry-all-errors)
  fi

  curl_cmd=(
    curl -sS -X POST
    "${BASE_URL}/v1beta/models/${MODEL}:generateContent"
    -H "Authorization: Bearer ${API_KEY}"
    -H "Content-Type: application/json"
    --connect-timeout "$CONNECT_TIMEOUT"
    --max-time "$MAX_TIME"
    --retry "$RETRY_MAX"
    --retry-delay "$RETRY_DELAY"
  )
  if [[ ${#curl_retry_extra[@]} -gt 0 ]]; then
    curl_cmd+=("${curl_retry_extra[@]}")
  fi
  curl_cmd+=(--data-binary "$payload" -o "$tmp_resp" -w "%{http_code}")
  http_status=$("${curl_cmd[@]}")
  if [[ "$http_status" != "200" ]]; then
    echo "Request failed: HTTP $http_status (index=$idx)" >&2
    head -c 400 "$tmp_resp" >&2 || true
    echo >&2
    exit 1
  fi

  decode_output="$(decode_to_png "$tmp_resp" "$out_path")"
  # Enforce explicit aspect ratio via center-crop if backend ignores it.
  if [[ -n "$ENV_ASPECT_RATIO" ]]; then
    CROP_RATIO="$ENV_ASPECT_RATIO" python - <<'PY' "$out_path"
import os
import sys
from PIL import Image

path = sys.argv[1]
ratio = os.environ.get("CROP_RATIO", "")
if not ratio or ":" not in ratio:
    sys.exit(0)
try:
    a, b = ratio.split(":")
    a = float(a)
    b = float(b)
    if a <= 0 or b <= 0:
        sys.exit(0)
    target = a / b
except Exception:
    sys.exit(0)

with Image.open(path) as im:
    w, h = im.size
    if w == 0 or h == 0:
        sys.exit(0)
    curr = w / h
    # If already close enough, skip.
    if abs(curr - target) < 0.005:
        sys.exit(0)
    if curr > target:
        new_w = int(round(h * target))
        left = max(0, (w - new_w) // 2)
        box = (left, 0, left + new_w, h)
    else:
        new_h = int(round(w / target))
        top = max(0, (h - new_h) // 2)
        box = (0, top, w, top + new_h)
    im.crop(box).save(path, format="PNG")
PY
  fi
  echo "$decode_output"
  saved_paths+=("$out_path")
done

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))

echo "generated_count ${#saved_paths[@]}"
echo "elapsed_seconds ${elapsed}"
