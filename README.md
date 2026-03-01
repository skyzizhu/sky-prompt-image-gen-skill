# sky-prompt-image-gen-skill

一个面向“提示词驱动生图”的技能：
- 输入提示词，可智能优化提示词；
- 自动解析提示词中的比例16:9、4:3等等；
- 自动解析提示词中的清晰度（1K/2K/4K）；
- 提示词过于简单时进行规则化扩写（由大模型完成）；
- 将解析结果与最终提示词组成 JSON，再调用生成脚本；

## 目录结构

- `skill/SKILL.md`：技能说明与交互规则
- `skill/scripts/`：生成与解析脚本
- `skill/config/`：配置文件目录

## 配置说明

### 0. 运行依赖

在使用前请确保：

- 已安装 `python3`
- 已安装 `Pillow`（用于解码并保存 PNG）：`pip install pillow`

### 1. API Key

在终端设置环境变量：

```bash
export GEMINI_IMAGE_API_KEY="你的key"
```

### 2. Base URL 与默认参数

编辑配置文件：

```
skill/config/prompt_image_gen.conf
```

示例（请根据你的服务端点修改）：

```bash
# Base URL for Gemini-compatible image endpoint
BASE_URL="https://www.example.com"

# Image generation model
MODEL="gemini-3.1-flash-image-preview"

# Defaults
ASPECT_RATIO="16:9"
IMAGE_SIZE="2K"  # use uppercase K (e.g., 1K/2K/4K)

# Network and retry
CONNECT_TIMEOUT="10"
MAX_TIME="180"
RETRY_MAX="3"
RETRY_DELAY="2"

# Debug logging (0 or 1)
DEBUG="0"
```

说明：
- **API Key 不写入配置文件**，请使用环境变量 `GEMINI_IMAGE_API_KEY`。
- 建议在提示词中明确写出“图片比例”和“清晰度/大小（如 2K/4K，K 为大写）”，以便精准解析与生成。
- 当前生图模型支持 Google 的两个模型：
  1. `gemini-3-pro-image-preview`
  2. `gemini-3.1-flash-image-preview`

## Gemini 3.1 Flash Image 支持的比例

根据 Gemini API 文档，`gemini-3.1-flash-image-preview` 支持的宽高比包括：

- `1:1`
- `1:4`
- `1:8`
- `2:3`
- `3:2`
- `3:4`
- `4:1`
- `4:3`
- `4:5`
- `5:4`
- `8:1`
- `9:16`
- `16:9`
- `21:9`

## 使用方法

### 单条提示词

```bash
GEMINI_IMAGE_API_KEY="你的key" \
./skill/scripts/gen_from_prompt.sh "设计一张 4:3 的科技海报，清爽留白"
```

### 多条提示词并行

```bash
GEMINI_IMAGE_API_KEY="你的key" \
CONCURRENCY="3" \
./skill/scripts/gen_multi_prompts.sh \
  --prompt "生成一张 8:1 的城市全景图，北京-上海-香港，4K" \
  --prompt "生成一张 16:9 的产品海报，清爽科技风" \
  --prompt "国风山水，水墨意境，层峦叠嶂"
```

## 输出

- 图片输出目录：`image_out/YYYYMMDD/`
- 生成过程中会输出 JSON，包含：
  - `prompt`（原始提示词）
  - `used_prompt`（最终提示词）
  - `aspect_ratio` / `image_size`

## 备注

- 若提示词未包含比例与清晰度，则读取 `prompt_image_gen.conf` 默认值。
- 提示词过于简单时，建议由大模型先优化后再传入脚本（流程已内置）。
