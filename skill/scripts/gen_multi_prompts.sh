#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONCURRENCY="${CONCURRENCY:-2}"
COUNT="${COUNT:-1}"
OUT_PREFIX="${OUT_PREFIX:-batch}"
PROMPTS_FILE="${PROMPTS_FILE:-}"

# Try to load user env if key is missing in non-login shells.
if [[ -z "${GEMINI_IMAGE_API_KEY-}" ]]; then
  [[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
  [[ -f "$HOME/.bash_profile" ]] && source "$HOME/.bash_profile"
fi

declare -a PROMPTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --prompt" >&2
        exit 1
      fi
      PROMPTS+=("$2")
      shift 2
      ;;
    --prompts-file)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --prompts-file" >&2
        exit 1
      fi
      PROMPTS_FILE="$2"
      shift 2
      ;;
    --concurrency)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --concurrency" >&2
        exit 1
      fi
      CONCURRENCY="$2"
      shift 2
      ;;
    --count)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --count" >&2
        exit 1
      fi
      COUNT="$2"
      shift 2
      ;;
    --out-prefix)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --out-prefix" >&2
        exit 1
      fi
      OUT_PREFIX="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: gen_multi_prompts.sh [--prompt \"...\"]... [--prompts-file file] [--concurrency 3] [--count 1] [--out-prefix batch]" >&2
      exit 1
      ;;
    *)
      PROMPTS+=("$1")
      shift
      ;;
  esac
done

if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || [[ "$CONCURRENCY" -lt 1 ]]; then
  echo "CONCURRENCY must be a positive integer" >&2
  exit 1
fi
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "COUNT must be a positive integer" >&2
  exit 1
fi

if [[ -n "$PROMPTS_FILE" ]]; then
  if [[ ! -f "$PROMPTS_FILE" ]]; then
    echo "prompts file not found: $PROMPTS_FILE" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    [[ "${trimmed:0:1}" == "#" ]] && continue
    PROMPTS+=("$trimmed")
  done < "$PROMPTS_FILE"
fi

if [[ "${#PROMPTS[@]}" -eq 0 ]]; then
  echo "No prompts provided. Use --prompt, positional prompts, or --prompts-file." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir" || true
}
trap cleanup EXIT

start_ts=$(date +%s)

declare -a pids=()
declare -a ids=()
failed=0

wait_one() {
  local pid="$1"
  local id="$2"
  if ! wait "$pid"; then
    failed=$((failed + 1))
    echo "[job ${id}] failed" >&2
    if [[ -s "$tmp_dir/${id}.err" ]]; then
      cat "$tmp_dir/${id}.err" >&2
    fi
  fi
}

for idx in "${!PROMPTS[@]}"; do
  prompt_index=$((idx + 1))
  prompt_text="${PROMPTS[$idx]}"
  pref="${OUT_PREFIX}_p$(printf '%02d' "$prompt_index")"
  detected_ratio="$(PROMPT="$prompt_text" python - <<'PY'
import os
import re
text = os.environ.get("PROMPT", "")
pat = re.compile(r"(\d{1,2})\s*[:：xX]\s*(\d{1,2})")
m = pat.search(text)
if m:
    print(f"{m.group(1)}:{m.group(2)}")
PY
)"

  (
    if [[ -n "${GEMINI_IMAGE_API_KEY-}" ]]; then
      export GEMINI_IMAGE_API_KEY
    fi
    COUNT="$COUNT" \
    OUT_PREFIX="$pref" \
    "$SCRIPT_DIR/gen_from_prompt.sh" "$prompt_text"
  ) >"$tmp_dir/${prompt_index}.out" 2>"$tmp_dir/${prompt_index}.err" &

  pids+=("$!")
  ids+=("$prompt_index")

  if [[ "${#pids[@]}" -ge "$CONCURRENCY" ]]; then
    wait_one "${pids[0]}" "${ids[0]}"
    pids=("${pids[@]:1}")
    ids=("${ids[@]:1}")
  fi
done

for i in "${!pids[@]}"; do
  wait_one "${pids[$i]}" "${ids[$i]}"
done

generated=0
for idx in "${!PROMPTS[@]}"; do
  prompt_index=$((idx + 1))
  if [[ -s "$tmp_dir/${prompt_index}.out" ]]; then
    echo "=== prompt_${prompt_index} ==="
    cat "$tmp_dir/${prompt_index}.out"
    c="$(awk '/^saved /{n++} END{print n+0}' "$tmp_dir/${prompt_index}.out")"
    generated=$((generated + c))
  fi
done

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
echo "batch_prompt_count ${#PROMPTS[@]}"
echo "batch_failed_count ${failed}"
echo "batch_generated_count ${generated}"
echo "batch_elapsed_seconds ${elapsed}"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
