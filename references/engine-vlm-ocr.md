# VLM OCR 引擎指南（PaddleOCR-VL vs Unlimited-OCR）

两个文档专用视觉大模型（VLM），作为 PP-StructureV3 失效后的重型兜底。默认不安装。

## 一、为什么优先 PaddleOCR-VL 而非 Unlimited-OCR

| 维度 | PaddleOCR-VL 1.6 | Unlimited-OCR |
|---|---|---|
| 参数 | 0.9B | 3.3B |
| GGUF 体积 | 全套约 1–1.5GB（语言模型 Q4 约 300MB + mmproj） | Q8 2.91GB / 约 6GB 内存；BF16 5.47GB |
| OmniDocBench | 96.3%（v1.6，SOTA） | 未在该榜单领先 |
| 横评综合精度 | 第一（词义 36/40、例句 40/40、零循环） | 词义 27/40、例句 36/40、**1/5 页重复循环** |
| 语言 | 109–111 语言，手写/古籍/印章/扭曲拍照 | 以中英文档为主 |
| CPU 部署 | llama.cpp 官方合入（b8110，2026-02） | 仅 unlocr 第三方封装（补丁版 llama.cpp，PR 未合并） |
| 独有能力 | 印章识别、跨页表格合并、手写 | **R-SWA 跨页工作记忆**（整本连续解析不"失忆"） |
| 许可 | Apache-2.0 | MIT |

**结论**：常规复杂文档用 PaddleOCR-VL；只有超长跨页整本（>50 页连续、需要页间上下文）才考虑 Unlimited-OCR。

来源：girlmoony/ocr-model-comparison 横评（RTX 4060Ti，5 张手机拍照的词汇书跨页，40 词条）、PaddleOCR 官方仓库、Unlimited-OCR 官方仓库、insiderllm GGUF 分析。

---

## 二、PaddleOCR-VL（首选重型）

### 2.1 部署路线 A：llama.cpp GGUF（推荐，CPU 可跑）

PaddleOCR-VL 已于 2026-02-19 合入 llama.cpp（build b8110）。GGUF 量化后语言模型约 300MB（Q4_K_M），加视觉 projector 全套约 1–1.5GB 内存，4GB 内存的机器就能跑。

```bash
# 1. 装 llama.cpp（需 ≥ b8110）
brew install llama.cpp
# 或源码编译: git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp && cmake -B build && cmake --build build --config Release

# 2. 下载 GGUF 模型（社区量化版，示例仓库，以实际可用为准）
#    语言模型: PaddleOCR-VL-1.5-0.9B-Q4_K_M.gguf（约 300MB）
#    视觉投影: mmproj-PaddleOCR-VL-1.5.gguf（约 880MB BF16，可进一步量化）
#    chat_template.jinja（必须，否则崩溃）
#    搜索 HuggingFace: paddleocr-vl gguf

# 3. 启动服务
llama-server \
  -m PaddleOCR-VL-1.5-0.9B-Q4_K_M.gguf \
  --mmproj mmproj-PaddleOCR-VL-1.5.gguf \
  -c 20000 --fit off \
  --jinja --chat-template-file chat_template.jinja \
  --host 127.0.0.1 --port 8080

# 4. 调用（OpenAI 兼容 API）
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "PaddleOCR-VL",
    "messages": [{"role": "user", "content": [
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}},
      {"type": "text", "text": "Extract all text from this document, output Markdown."}
    ]}],
    "max_tokens": 4096
  }'
```

**关键坑**：必须传 `--jinja --chat-template-file chat_template.jinja`，否则模型崩溃（图像占位符 token 处理需要）。

### 2.2 部署路线 B：PaddlePaddle 官方后端（GPU 优先）

```bash
# 独立 3.12 venv
pip install paddlepaddle "paddleocr[doc-parser]>=3.7.0"
```
```python
from paddleocr import PaddleOCRVL
pipeline = PaddleOCRVL(device="cpu")  # macOS 用 cpu；GPU 用 gpu:0
result = pipeline.predict("document.pdf")
# result[0].res["md"]
```
注意：官方 vLLM/SGLang 服务端路线**不支持 macOS 原生**（需 Docker）；macOS 上用 Paddle 动态后端 device="cpu" 或 llama.cpp GGUF。

### 2.3 局限
- llama.cpp 路线只是 Stage 2（VLM 识别），**不含 PP-DocLayout 版面前置**。简单文档（单页文字、单表、发票）足够；复杂混合页（多栏+表格+公式+图片交错）建议用完整 Paddle 管线（路线 B）或先 PP-StructureV3。
- 不是通用视觉模型，别拿它描述普通照片。
- CPU 上慢（GPU 实测 76–141s/页，CPU 更慢），适合质量优先、不赶时间的场景。

---

## 三、Unlimited-OCR（特化备选，仅超长跨页整本）

### 3.1 独有价值
R-SWA（Ring Sliding Window Attention）跨页工作记忆：一次性输入多页/整份 PDF，页间不"失忆"，适合几百页的书、长篇报告连续解析。这是 PaddleOCR-VL 没有的。

### 3.2 部署：unlocr（GGUF + 补丁版 llama.cpp）

官方路线（transformers/vLLM/SGLang）仅 CUDA，本机不可用；MLX 路线仅 Apple Silicon，本机不可用；OpenVINO 研究版 CPU 仅 0.049 tok/s，不可用。**本机唯一可行是 unlocr**。

```bash
# 1. 装依赖
brew install poppler   # 提供 pdftoppm
brew install whit3rabbit/tap/unlocr

# 2. 跑（首次自动下载补丁版 llama-server 和 Q8 模型，约 3GB）
unlocr document.pdf --out ./out --quality good
# --quality: less(Q4_K_M,1.82GB) / good(Q8_0,2.91GB,默认) / best(BF16,5.47GB)
# --task: markdown(默认) / grounding(带坐标) / free(纯文本) / figure(图表解析)

# 输出: ./out/document.md，分页用 <!-- page N --> 标记
```

### 3.3 必须加的守卫（重复循环问题）
横评显示 Unlimited-OCR 会在 1/5 页上陷入重复循环。生产使用必须：
1.  cap `max_tokens`（如 8192）
2.  检测输出中连续重复的 n-gram（如连续 3 次相同句子）
3.  触发后用 base 配置重试（1024px、crop 关闭）
4.  unlocr 的 `--max-tokens` 参数可设上限

### 3.4 风险与注意
- **WIP 项目**：unlocr 仍在活跃开发，API 可能变
- **第三方补丁版 llama.cpp**：R-SWA 支持的 PR（#24975）未合入上游 llama.cpp，unlocr 用自己 CI 编译的补丁版。供应链上信任 unlocr 的构建
- **CPU 速度**：Apple M 系列 BF16 约 7.2s/页（355 页书 42 分钟）；Intel CPU 跑量化档会更慢，整本大文档建议后台跑
- **模型缓存**：`~/Library/Caches/unlocr/`，可删可换
- **卸载**：`brew uninstall unlocr`，删缓存目录

---

## 四、选型决策

```
PP-StructureV3 失效？
  ├─ 否 → 用 StructureV3（更快、更稳、给坐标）
  └─ 是 → 文档是超长跨页整本（>50 页连续）？
            ├─ 否 → PaddleOCR-VL（更小、更准、零循环、CPU 路径成熟）
            └─ 是 → Unlimited-OCR/unlocr（跨页记忆，加重复守卫）
```

## 五、来源
- PaddleOCR-VL 官方：https://github.com/PaddlePaddle/PaddleOCR 、http://www.paddleocr.ai/latest/version3.x/pipeline_usage/PaddleOCR-VL.html
- llama.cpp 合入：build b8110（2026-02-19）
- GGUF 分析：https://insiderllm.com/pdfs/paddleocr-vl-local-document-ocr.pdf
- Unlimited-OCR 官方：https://github.com/baidu/Unlimited-OCR
- unlocr：https://github.com/whit3rabbit/unlocr
- 横评：https://github.com/girlmoony/ocr-model-comparison
- OpenVINO 研究版（不推荐）：https://github.com/sublatesublate-design/unlimited-ocr-openvino
