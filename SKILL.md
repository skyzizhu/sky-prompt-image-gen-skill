---
name: sky-prompt-image-gen-skill
description: 极简生图技能。当用户说“生成图片”“生图”“生成一张图/多张图”时使用。用户只需要提供 PROMPT，即可调用图像 API 生成图片；支持一次生成多张。
---

# Sky Simple Image Gen Skill

## Overview

这是一个极简生图 skill。默认只需要用户提供 `PROMPT`，即可调用 API 生成图片。

支持能力：

- 单张图片生成
- 单提示词多张生成（`COUNT`）
- 多提示词并行生成（batch prompts）
- 比例和分辨率控制（可选）
- 自定义输出前缀（可选）

## When to Use

- 用户明确说“生成图片”“生图”“生成一张图”“生成多张图”
- 用户明确说“按多个提示词一起生图”“批量生图”
- 用户明确要“根据提示词生成图片”
- 用户不需要复杂模板，只想直接生图
- 用户希望一次生成多张候选图

## Required Inputs

- `PROMPT`: 生图提示词
- `GEMINI_IMAGE_API_KEY`: 环境变量中的 API Key

## Optional Inputs

- `COUNT`: 生成张数，默认 `1`
- `ASPECT_RATIO`: 例如 `16:9`、`9:16`、`3:4`
- `IMAGE_SIZE`: 默认 `2K`
- `OUT`: 单张输出文件名（仅 `COUNT=1` 时生效）
- `OUT_PREFIX`: 多图输出文件名前缀，默认 `generated`
- `CONFIG_FILE`: 自定义配置文件路径

## Script

主脚本：

- `scripts/gen_images.sh`
- `scripts/gen_multi_prompts.sh`（多提示词并行）

默认使用配置文件：

- `config/simple_image_gen.conf`

### Usage

单张（只传提示词）：

```bash
GEMINI_IMAGE_API_KEY="你的key" \
./scripts/gen_from_prompt.sh "赛博朋克城市夜景，霓虹灯，电影感"
```

单张（提示词包含比例时，助手需显式传入）：

```bash
GEMINI_IMAGE_API_KEY="你的key" \
./scripts/gen_from_prompt.sh "设计一张 4:3 的科技海报，清爽留白"
```

多张（同一提示词一次出 4 张）：

```bash
GEMINI_IMAGE_API_KEY="你的key" \
COUNT="4" \
OUT_PREFIX="city_night" \
./scripts/gen_from_prompt.sh "赛博朋克城市夜景，霓虹灯，电影感"
```

带比例：

```bash
GEMINI_IMAGE_API_KEY="你的key" \
COUNT="3" \
./scripts/gen_from_prompt.sh "未来感AI实验室，蓝色冷光，简洁科技"
```

多提示词并行（推荐）：

```bash
GEMINI_IMAGE_API_KEY="你的key" \
CONCURRENCY="3" \
/Users/skyzizhu/.codex/skills/sky-simple-image-gen-skill/scripts/gen_multi_prompts.sh \
  --prompt "未来感AI实验室，蓝色冷光，简洁科技" \
  --prompt "国风山水，水墨意境，层峦叠嶂" \
  --prompt "极简白底产品海报，现代感"
```

从文件批量读取提示词并并行生成：

```bash
GEMINI_IMAGE_API_KEY="你的key" \
CONCURRENCY="4" \
/Users/skyzizhu/.codex/skills/sky-simple-image-gen-skill/scripts/gen_multi_prompts.sh \
  --prompts-file /path/to/prompts.txt
```

## Output

- 输出目录固定：`image_out/YYYYMMDD/`
- 自动保存为 PNG
- 如果重名会自动追加 `(1)`, `(2)` 后缀，避免覆盖

## Conversation Rules

1. 用户给出提示词后，直接执行，不需要复杂追问。
2. 若用户未给出张数，默认 `COUNT=1`。
3. 若用户说“一个提示词多张图”，使用 `COUNT`。
4. 若用户说“多个提示词一起生图”，使用 `gen_multi_prompts.sh` 并行执行。
5. **助手先解析提示词中的比例与清晰度信息（如 `4:3`、`16:9`、`3:4`、`1K`、`2K`、`4K` 等）。**
6. **将解析结果与提示词组成 JSON，交由 `gen_from_prompt.sh` 处理并调用 `gen_images.sh`。**
7. **若未解析到比例与清晰度：`gen_from_prompt.sh` 读取 `simple_image_gen.conf` 中的默认 `ASPECT_RATIO` 与 `IMAGE_SIZE`。**
8. **若提示词过于简单：由大模型先做规则化扩写（不改变核心语义），再传给脚本。**
9. 多提示词时：对每条提示词分别进行“简洁提示词优化 + 比例/清晰度解析 + 生成 JSON + 调用生成脚本”，并逐条汇总输出结果。
10. 生成完成后，**必须告知用户**：
   - 最终提示词（`used_prompt`）
   - 比例（`aspect_ratio`）
   - 清晰度/大小（`image_size`，如 `2K`）
   - 最终图片路径（若失败，明确告知失败原因或失败状态）
11. 可选：简要输出生成耗时。

### 比例与清晰度解析规则（由大模型执行）

- 识别文本中的比例表达：`4:3`、`16:9`、`3:4`、`9:16`、`1:1`、`2:3`、`3:2`、`8:1` 等。
- 允许中文/英文混排与全角符号（如 `4：3`）。
- 若出现多个比例，以**最明确**或**最靠近“比例/尺寸/画幅”描述的那一个**为准。
- 识别清晰度表达：`1K`、`2K`、`4K`（不区分大小写）。
- 若出现多个清晰度，以**最明确**或**最靠近“清晰度/分辨率/画质”描述的那一个**为准。
- 解析结果仅用于 `ASPECT_RATIO` 与 `IMAGE_SIZE` 参数，提示词原样保留。

### JSON 结构（由 `gen_from_prompt.sh` 生成并传递）

```json
{
  "prompt": "原始提示词",
  "used_prompt": "规则化扩写后的提示词（若未扩写则与原文一致）",
  "optimized": true,
  "aspect_ratio": "4:3",
  "image_size": "2K",
  "source": {
    "aspect_ratio": "prompt",
    "image_size": "config"
  }
}
```

## Notes

- 比例优先级：**提示词显式比例（由助手解析并传入） > `simple_image_gen.conf` 默认比例**。
