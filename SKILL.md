---
name: work-doc-extract
description: 本地工作文档（PDF / 扫描件 / DOCX / PPTX / XLSX / CSV / 图片）的内容提取与 OCR 工具箱，统一输出 Markdown。当用户要"把这个 PDF/讲义/扫描件/Word/PPT/表格/图片转成文字或 Markdown""OCR 识别""提取文档内容""扫描件转可搜索文本""表格识别""公式识别""文档结构化""批量 OCR"时使用。内置五层引擎选型：文本层直取 → macOS Vision（纯文字默认，零安装）→ PP-StructureV3（表格/公式/多栏/图表结构化，确定性管线）→ PaddleOCR-VL 0.9B（重型 VLM 兜底，GGUF 可 CPU 跑）→ Unlimited-OCR（超长跨页整本特化），含断点续跑、页数对账校验门、批量处理与依赖自检。
compatibility: "仅在 macOS(Darwin) 实测可用；Windows/Linux 未适配。执行前先判平台(uname -s 返回 Darwin)，非 macOS 停止并告知需另行适配、不硬跑；将来补齐 Windows 后仍按平台分流并分别标注验证状态"
---

# work-doc-extract — 工作文档提取与 OCR

## 平台适用（执行前先读）
- 本技能当前**仅在 macOS（Darwin）实测可用**，命令、路径、代理端口与系统原生能力均按 Mac。
- 动手前先判平台：`uname -s` 返回 `Darwin` 才走本技能流程；**Windows/Linux 未适配，遇到就停下告知用户“需先做该平台适配”，不要用想当然的等价命令硬跑**。
- 以后补齐 Windows 后也必须保留“先判平台 → 按平台分流”的结构：mac/Windows 的命令与路径分开写、各自标注是否已验证。

把任意工作文档变成可搜索、可引用的 Markdown。核心是**引擎选型**和**校验门**，不是某个单一 OCR。

## 1. 核心原则

1. **能用轻的不用重的**：有文本层就不 OCR；纯文字就用 Vision；只有表格/公式/多栏/手写才升级到结构化管线或 VLM。
2. **确定性优先于 VLM**：PP-StructureV3 是模块拼装、不幻觉、不重复循环、给坐标；VLM（PaddleOCR-VL / Unlimited-OCR）只在确定性管线失效时启用。
3. **本地优先、离线可用**：默认引擎（Vision + PyMuPDF + Office 解析库）零联网；PaddleOCR / VLM 是可选重型后端，默认不安装，用到再装。
4. **校验后交付**：任何 OCR/抽取结果必须过校验门（页数对账、空页、乱码替换字符、首尾抽样回读），不通过就重跑或换引擎。
5. **来源可追溯**：输出 Markdown 头部记录源文件、所用引擎、时间、页数；分页用统一标记。

## 2. 引擎选型速查

按文档内容复杂度逐级升级。完整能力矩阵与决策依据见 [`references/backend-selection.md`](references/backend-selection.md)。

| 层级 | 触发条件 | 首选引擎 | 备选 |
|---|---|---|---|
| 第 0 层 | PDF 有文本层 / DOCX / PPTX / XLSX / CSV | 直接解析（PyMuPDF / python-docx / python-pptx / openpyxl） | — |
| L1 纯文字行 | 图片型 PDF / 扫描件 / 图片，内容是连续文字 | **macOS Vision**（零安装、约 1s/页） | PP-OCRv6（跨平台 / 多语言 / 竖排 / 要坐标） |
| L2 要结构 | 含表格 / 公式 / 多栏 / 图表 / 印章，需要保留版式 | **PP-StructureV3**（确定性管线、给坐标、不循环） | — |
| L3 语义兜底 | L2 失效：手写 / 拍照扭曲 / 复杂语义 / 质量差 | **PaddleOCR-VL 0.9B**（GGUF 全套约 1–1.5GB，CPU 可跑） | Unlimited-OCR（仅超长跨页整本） |
| 在线补充 | 只有零星几页、或要图表语义描述 | 豆包多模态视觉（零安装） | — |

**各引擎安装、参数、坑、实测数据**：
- Vision：[`references/engine-vision.md`](references/engine-vision.md)
- PaddleOCR（PP-OCRv6 + PP-StructureV3）：[`references/engine-paddleocr.md`](references/engine-paddleocr.md)
- VLM（PaddleOCR-VL GGUF vs Unlimited-OCR / unlocr）：[`references/engine-vlm-ocr.md`](references/engine-vlm-ocr.md)

## 3. 统一处理流程

```
输入文件/目录
  → ① 判型（扩展名 + file 魔数 + PDF 文本层探测）
  → ② 按上表选引擎
  → ③ 抽取 / OCR（批量时断点续跑）
  → ④ 统一 Markdown：来源头 + 分页标记 + 正文
  → ⑤ 校验门（不通过→换引擎或重跑）
  → ⑥ 交付 .md（批量附校验汇总）
```

### 3.1 判型要点

- **PDF 文本层探测**：用 PyMuPDF 逐页 `get_text("text")`，若平均每页可提取字符 < 阈值（默认 20），判定为图片型 PDF，走 OCR；否则直接抽取文本层。
- **图片型 PDF 的表格/公式页**：Vision 批量跑完后，对疑似复杂页（OCR 结果出现大量碎片 / 数字矩阵 / `=` 密集）再用 PP-StructureV3 或 AI 视觉补，不必整本上重引擎。
- **Office 格式**：DOCX/PPTX/XLSX 永远直接解析，不走 OCR（除非是扫描后塞进 Word 的图片，那应先提取图片再 OCR）。

### 3.2 统一输出约定

- 文件名：`<原名>_extracted.md`（OCR 产物可用 `<原名>_OCR.md`，与项目惯例兼容）。
- 头部元信息（YAML 或引用块）：源文件、所用引擎、处理时间、总页数、DPI（如适用）。
- 分页标记：PDF/多页用 `## 第 N 页` + `---` 分隔；Office 文档按章节/幻灯片/工作表分节。
- 表格：Markdown 表格；公式：LaTeX（行内 `$...$`，块级 `$$...$$`）。

## 4. 脚本索引

所有脚本在 `scripts/`，优先用 `extract_text.py` 统一入口；单一场景可直接调专用脚本。

| 脚本 | 用途 | 典型用法 |
|---|---|---|
| `extract_text.py` | **统一入口**：判型 + 文本层/Office 抽取 + 调度 Vision OCR，输出 Markdown | `python3 scripts/extract_text.py input.pdf -o out.md` |
| `pdf_ocr.sh` | 图片型 PDF 批量 OCR（Vision），断点续跑、ETA、后处理、汇总 | `bash scripts/pdf_ocr.sh input.pdf [输出目录]` |
| `ocr_vision.swift` | macOS Vision 单图 OCR（被 pdf_ocr.sh 调用，也可单独用） | `swift scripts/ocr_vision.swift page.png` |
| `verify_extract.py` | 校验门：页数对账、空页、替换字符乱码、抽样 | `python3 scripts/verify_extract.py out.md --source input.pdf` |
| `bootstrap.sh` | 依赖自检：检测 python / PyMuPDF / swift / PaddleOCR / llama.cpp 等是否可用，给出安装命令（不自动装重型后端） | `bash scripts/bootstrap.sh` |

**PP-StructureV3 / PaddleOCR-VL / Unlimited-OCR 不提供封装脚本**：它们是可选重型后端，按 `references/` 中对应指南的命令直接调用（参数多、变化快，封装反而易过时）。`bootstrap.sh` 只检测可用性。

## 5. 校验门（强制，交付前必过）

完整细则见 [`references/verification.md`](references/verification.md)。核心四项：

1. **页数对账**：输出 Markdown 的分页节数 ≥ 源 PDF 页数（少于即残缺，重跑）。
2. **空页 / 重复页检测**：连续空白页、内容完全相同的相邻页标记出来。
3. **乱码 / 替换字符**：统计 `�`、连续乱码字符、异常高比例标点，超阈值告警。
4. **首尾抽样回读**：人工或 AI 抽查第 1 页、中间 1 页、最后 1 页，确认无截断、无错位、表格结构正确。

校验不通过时：先看是否单页失败（重跑该页），再考虑换引擎（Vision → PP-StructureV3 → VLM）。

## 6. 与其他技能的边界（防重复建设）

| 任务 | 用哪个 | 本技能做什么 |
|---|---|---|
| Excel/CSV 的创建、计算、分析、美化、可视化 | 系统 `sheet` 技能（强制） | 只做"从 xlsx/csv 快速抽取文本与表格到 Markdown" |
| PDF 的编辑、合并、拆分、表单填写、页面操作、加密 | 系统 `doubao-pdf` | 只做"PDF 内容提取与 OCR" |
| 飞书在线文档 / 多维表格的读写 | `lark-doc` / `lark-base` | 不碰在线文档 |
| 截图 / 长图 / 文本的敏感信息脱敏打码 | 你已有的 `image-text-redact` | 不做脱敏；其 OCR 定位模式可参考 |
| 视频 / 音频转文字 | 其他技能 | 不处理音视频 |

## 7. 环境与依赖

- **必需（默认引擎）**：Python 3.10+、`pymupdf`、macOS 上 `swift`（Vision）。Office 格式按需装 `python-docx` / `python-pptx` / `openpyxl`。
- **可选重型（默认不装）**：PaddleOCR（PP-OCRv6 + StructureV3，需独立 Python 3.12 venv，macOS 仅 CPU 版）、PaddleOCR-VL（llama.cpp ≥ b8110 + GGUF）、Unlimited-OCR（unlocr + 补丁版 llama.cpp）。
- **先跑 `bash scripts/bootstrap.sh`** 看本机有什么，再决定装什么。不要把重型后端装进项目的转写 venv（会污染 FunASR 依赖），用独立 venv。
- 系统 Python 若为 3.13+，PaddlePaddle 暂不支持，必须建 3.12 venv。

## 8. 已知坑（来自实战）

- **iTerm 直接跑 OCR 脚本可能退出**：长任务用 `nohup ... &` + `tail -f` 日志，或用 `extract_text.py`（Python 进程更稳）。
- **中文 + bash 变量拼接报 unbound variable**：脚本里已设 `LANG/LC_ALL=en_US.UTF-8` 兜底；自己写循环时注意。
- **Vision 不保留表格结构**：不要指望它出 Markdown 表格，表格页必须升级到 PP-StructureV3 或 AI 视觉。
- **VLM 会重复循环**：PaddleOCR-VL 横评零循环，但 Unlimited-OCR 会；用 Unlimited-OCR 时必须加重复检测 + 重试守卫（见 engine-vlm-ocr.md）。
- **OCR 错字后处理**：常见专有名词识别错误（如品牌名、人名）用 sed 替换表修正，替换表可配置，不要硬编码在脚本里。
- **大 PDF 内存**：PyMuPDF 逐页处理，不要一次性 `load_page` 全部；临时图片用完即删，只留 txt 缓存供断点续跑。
