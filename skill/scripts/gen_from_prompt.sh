#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config/prompt_image_gen.conf}"

if [[ -z "${1-}" ]]; then
  echo "missing prompt" >&2
  exit 1
fi

PROMPT="$1"

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
export ASPECT_RATIO
export IMAGE_SIZE

"$SCRIPT_DIR/gen_images.sh" "$USED_PROMPT"
