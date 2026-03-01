#!/usr/bin/env python3
import json
import os
import re
import sys
from typing import Optional


def read_config(path: str) -> dict:
    cfg = {}
    if not path or not os.path.exists(path):
        return cfg
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            cfg[k] = v
    return cfg


def detect_ratio(text: str) -> Optional[str]:
    # Match x:y, x：y, x/y, x比y (with optional spaces)
    m = re.search(r"(\d{1,2})\s*(?:[:：/xX]|比)\s*(\d{1,2})", text)
    if not m:
        return None
    return f"{m.group(1)}:{m.group(2)}"


def detect_size(text: str) -> Optional[str]:
    # Match 1k/2k/4k (case-insensitive), tolerate trailing Chinese/punct/spaces.
    # Allow cases like "4k分辨率" while avoiding alphanumeric continuations like "4kg".
    m = re.search(r"([124])\s*[kK](?![A-Za-z])", text)
    if not m:
        return None
    return f"{m.group(1)}k"


def is_too_simple(text: str) -> bool:
    t = text.strip()
    if not t:
        return True
    # Heuristic: short prompts are likely too simple.
    if len(t) < 40:
        return True
    # If prompt is a simple "generate" request without visual details, treat as simple.
    if re.search(r"(生成|画|绘制|制作).{0,8}一张", t) and not re.search(
        r"(风格|光影|构图|色彩|质感|氛围|材质|写实|插画|电影感|景深|留白)", t
    ):
        return True
    # If mostly ASCII and few words, treat as simple.
    if all(ord(c) < 128 for c in t):
        words = [w for w in re.split(r"\\s+", t) if w]
        if len(words) <= 4:
            return True
    return False


def optimize_prompt(text: str) -> str:
    # Rule-based expansion (no model call).
    suffix = "高清细节，真实光影，层次清晰，构图平衡，质感自然"
    if text.endswith("。") or text.endswith("."):
        return text + suffix
    return text + "，" + suffix


def main() -> int:
    if len(sys.argv) < 2:
        print("missing prompt", file=sys.stderr)
        return 1
    prompt = sys.argv[1]
    original_prompt = os.environ.get("ORIGINAL_PROMPT", "")
    used_prompt_env = os.environ.get("USED_PROMPT", "")
    # Always use the default config next to scripts/ (no env dependency).
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_file = os.path.join(script_dir, "..", "config", "prompt_image_gen.conf")
    cfg = read_config(config_file)

    ratio = detect_ratio(prompt)
    size = detect_size(prompt)

    ratio_source = "prompt" if ratio else "config"
    size_source = "prompt" if size else "config"

    if not ratio:
        ratio = cfg.get("ASPECT_RATIO", "16:9")
    if not size:
        size = cfg.get("IMAGE_SIZE", "2k")

    # Normalize ratio to ASCII colon and size to lowercase.
    if isinstance(ratio, str):
        ratio = ratio.replace("：", ":")
    if isinstance(size, str):
        size = size.lower()

    optimized = False
    used_prompt = prompt
    # If assistant already optimized, trust it.
    if used_prompt_env:
        used_prompt = used_prompt_env
        optimized = (original_prompt and used_prompt_env != original_prompt) or False
    else:
        if is_too_simple(prompt):
            used_prompt = optimize_prompt(prompt)
            optimized = True

    out = {
        "prompt": original_prompt or prompt,
        "used_prompt": used_prompt,
        "optimized": optimized,
        "aspect_ratio": ratio,
        "image_size": size,
        "source": {
            "aspect_ratio": ratio_source,
            "image_size": size_source,
        },
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
