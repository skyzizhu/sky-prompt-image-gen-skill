#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/prompt_image_gen.conf"

if [[ -z "${1-}" ]]; then
  echo "missing prompt" >&2
  exit 1
fi

PROMPT="$1"
shift

COUNT=""
OUT=""
OUT_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)
      [[ -z "${2-}" ]] && { echo "Missing value for --count" >&2; exit 1; }
      COUNT="$2"
      shift 2
      ;;
    --out)
      [[ -z "${2-}" ]] && { echo "Missing value for --out" >&2; exit 1; }
      OUT="$2"
      shift 2
      ;;
    --out-prefix)
      [[ -z "${2-}" ]] && { echo "Missing value for --out-prefix" >&2; exit 1; }
      OUT_PREFIX="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -n "${USED_PROMPT-}" ]]; then
  export USED_PROMPT
  export ORIGINAL_PROMPT="$PROMPT"
fi

json="$("$SCRIPT_DIR/build_gen_json.py" "$PROMPT")"
echo "$json"

ASPECT_RATIO="$(python - <<'PY' "$json"
import json,sys
obj=json.loads(sys.argv[1])
print(obj.get("aspect_ratio",""))
PY
)"

IMAGE_SIZE="$(python - <<'PY' "$json"
import json,sys
obj=json.loads(sys.argv[1])
print(obj.get("image_size",""))
PY
)"

USED_PROMPT="$(python - <<'PY' "$json"
import json,sys
obj=json.loads(sys.argv[1])
print(obj.get("used_prompt",""))
PY
)"

export CONFIG_FILE

set +e
gen_out="$("$SCRIPT_DIR/gen_images.sh" "$USED_PROMPT" "$ASPECT_RATIO" "$IMAGE_SIZE" "${COUNT:-1}" "${OUT:-}" "${OUT_PREFIX:-generated}" 2>&1)"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "status failed"
  echo "$gen_out"
  exit $status
fi

paths="$(printf '%s\n' "$gen_out" | awk '/^saved /{print $2}')"
elapsed="$(printf '%s\n' "$gen_out" | awk '/^elapsed_seconds /{print $2}')"

echo "used_prompt ${USED_PROMPT}"
echo "aspect_ratio ${ASPECT_RATIO}"
echo "image_size ${IMAGE_SIZE}"
echo "image_paths ${paths}"
echo "elapsed_seconds ${elapsed}"
