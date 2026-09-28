# engine-rapidocr.md — RapidOCR PP-OCRv6（L1 默认）

> 本文档是 work-doc-extract 技能 L1 默认引擎的安装、参数、坑、实测数据。

## 1. 是什么

[RapidOCR](https://github.com/RapidAI/RapidOCR) 是 PaddleOCR PP-OCRv6 的 ONNX Runtime 封装。不依赖 PaddlePaddle 框架，纯 Python + onnxruntime，CPU 跑，跨平台（macOS / Linux / Windows）。

为什么选它做 L1 默认：
- **pip 一条命令装完**，模型首次运行自动下载（~15MB）
- **跨平台**：macOS Vision 只能在 Mac，RapidOCR 任意机器都能跑
- **中文/数字/英文混排更准**：PP-OCRv6 比旧版 PP-OCRv5 再提 13%
- **CPU 即可**：M 系列 Mac 约 1.5 秒/页，和 Vision 差不多

## 2. 安装

```bash
# 推荐 Python 3.12（onnxruntime 暂不支持 3.14）
python3.12 -m venv .venv
.venv/bin/pip install rapidocr onnxruntime pymupdf
```

首次运行会自动下载三个模型到 `site-packages/rapidocr/models/`：
- `PP-OCRv6_det_small.onnx`（文字检测）
- `ch_ppocr_mobile_v2.0_cls_mobile.onnx`（方向分类）
- `PP-OCRv6_rec_small.onnx`（文字识别）

## 3. 用法

### 3.1 命令行（单 PDF）

```bash
.venv/bin/python scripts/ocr_rapid.py 讲义.pdf -o 讲义_OCR.md
.venv/bin/python scripts/ocr_rapid.py 讲义.pdf --dpi 200 --max-pages 10  # 试跑前10页
```

### 3.2 从 Python 调用

```python
from rapidocr import RapidOCR
ocr = RapidOCR()
result = ocr("page.png")          # 或 ocr(image_bytes)
lines = result.txts               # list[str]，逐行文本
```

### 3.3 走技能统一入口

```bash
bash scripts/pdf_ocr.sh 讲义.pdf [输出目录]   # 自动优先 RapidOCR
python3 scripts/extract_text.py 讲义.pdf       # 自动判型
```

## 4. 输出格式

与本技能其他引擎一致：

```markdown
# <书名>（OCR文字稿）

> 源文件: /abs/path.pdf | 引擎: RapidOCR PP-OCRv6 | 时间: 2026-09-20 15:30:00 | 共N页 | DPI 200

---
## 第1页

<逐行文本>

---
## 第2页
...
```

## 5. 性能实测（2026-09-20，M 系列 Mac，200 DPI）

| 指标 | 数据 |
|---|---|
| 模型加载 | 首次 ~2s，进程内 0.2s |
| 单页速度 | ~1.5s/页 |
| 断点续跑 | `<pdf名>.pages/<N>.txt`（PDF 同目录，跨 PDF 不串） |
| 识别质量 | 中文/标点/数字混排优于 macOS Vision；表格结构仍不出 |

## 6. 坑

- **Python 3.14 装不上**：onnxruntime 暂不支持，必须 3.12。
- **模型下载**：首次运行自动下载，国内网络慢可手动下放到 `~/.cache/rapidocr/models/`。
- **不出表格**：RapidOCR 只出文字行，要表格结构升级 PP-StructureV3 或 VLM。
- **不要和 PaddlePaddle 混装**：会污染依赖，RapidOCR 走 onnxruntime 不需要 paddle。
- **断点缓存目录**：`<pdf名>.pages/` 会留在 PDF 同目录，项目里要 gitignore。

## 7. 与 macOS Vision 的关系

- **默认 RapidOCR**：跨平台、更准、Python 进程稳
- **Vision 兜底**：`OCR_ENGINE=vision bash scripts/pdf_ocr.sh ...`，零 pip 依赖，应急用
- 两者输出格式完全一致，可互替换
